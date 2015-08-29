#!/bin/bash

# I run this in Raspbian chroot with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     chroot /chroot/raspbian/rust /ruststrap/armhf/build-snap.sh

set -x
set -e

: ${CHANNEL:=nightly}
: ${BRANCH:=master}
: ${DROPBOX:=~/dropbox_uploader.sh}
: ${SNAP_DIR:=/build/snapshot}
: ${SRC_DIR:=/build/rust}

# Set the channel
if [ ! -z $1 ]; then
  CHANNEL=$1
fi

# Configure the build
case $CHANNEL in
  stable)
    BRANCH=stable
  ;;
  beta)
    BRANCH=beta
  ;;
  nightly);;
  *) 
    echo "unknown release channel: $CHANNEL" && exit 1
  ;;
esac

start=$(date +"%s")
# checkout latest rust $BRANCH
cd $SRC_DIR
git checkout $BRANCH
git pull
git submodule update

# check if the latest snapshot has already been built
LAST_SNAP_HASH=$(head src/snapshots.txt | head -n 1 | tr -s ' ' | cut -d ' ' -f 3)
if [ ! -z "$($DROPBOX list snapshots | grep $LAST_SNAP_HASH)" ]; then
  # already there, nothing left to do
  exit 0
fi

#This is the second to last snapshot. This is the snapshot that should be used to build the next one
SECOND_TO_LAST_SNAP_HASH=$(cat src/snapshots.txt | grep "S " | sed -n 2p | tr -s ' ' | cut -d ' ' -f 3)
if [ -z "$($DROPBOX list snapshots | grep $SECOND_TO_LAST_SNAP_HASH)" ]; then
  # not here, we need this snapshot to continue
  echo "Need snapshot ${SECOND_TO_LAST_SNAP_HASH} to compile snapshot compiler ${LAST_SNAP_HASH}"
  exit 1
fi

# Use the second to last snapshot to build the next snapshot
# setup snapshot
cd $SNAP_DIR
rm -rf *
SNAP_TARBALL=$($DROPBOX list snapshots | grep ${SECOND_TO_LAST_SNAP_HASH}- | tr -s ' ' | cut -d ' ' -f 4)
$DROPBOX -p download snapshots/$SNAP_TARBALL
tar xjf $SNAP_TARBALL --strip-components=1

# build it
cd $SRC_DIR
git checkout $LAST_SNAP_HASH
cd build
../configure \
  --disable-docs \
  --disable-valgrind \
  --enable-ccache \
  --enable-clang \
  --disable-libcpp \
  --enable-local-rust \
  --enable-llvm-static-stdcpp \
  --local-rust-root=$SNAP_DIR \
  --build=arm-unknown-linux-gnueabihf \
  --host=arm-unknown-linux-gnueabihf \
  --target=arm-unknown-linux-gnueabihf
make clean
make -j$(nproc)
make -j$(nproc) snap-stage3-H-arm-unknown-linux-gnueabihf

# ship it
$DROPBOX -p upload rust-stage0-* snapshots
rm rust-stage0-*

# cleanup
rm -rf $SNAP_DIR/*
