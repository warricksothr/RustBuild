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

: ${DROPBOX:=~/dropbox_uploader.sh}
: ${SNAP_DIR:=/build/snapshot}
: ${SRC_DIR:=/build/rust}

# checkout latest rust
cd $SRC_DIR
git checkout master
git pull
git submodule update

# check if the latest snapshot has already been built
LAST_SNAP_HASH=$(head src/snapshots.txt | head -n 1 | tr -s ' ' | cut -d ' ' -f 3)
if [ ! -z "$($DROPBOX list snapshots | grep $LAST_SNAP_HASH)" ]; then
  # already there, nothing left to do
  exit 0
fi

# XXX here I should use the second to last snapshot hash in `snapshot.txt`, but
# in most cases it matches with the last stage0 rustc that was built
# setup snapshot
cd $SNAP_DIR
rm -rf *
SNAP_TARBALL=$($DROPBOX list snapshots | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
$DROPBOX -p download snapshots/$SNAP_TARBALL
tar xjf $SNAP_TARBALL --strip-components=1

# build it
cd $SRC_DIR
git checkout $LAST_SNAP_HASH
cd build
../configure \
  --disable-docs \
  --disable-inject-std-version \
  --disable-valgrind \
  --enable-ccache \
  --enable-llvm-static-stdcpp \
  --enable-local-rust \
  --local-rust-root=$SNAP_DIR \
  --build=arm-unknown-linux-gnueabihf \
  --host=arm-unknown-linux-gnueabihf \
  --target=arm-unknown-linux-gnueabihf
make clean
make -j$(nproc)
make snap-stage3-H-arm-unknown-linux-gnueabihf -j$(nproc)

# ship it
$DROPBOX -p upload rust-stage0-* snapshots
rm rust-stage0-*

# cleanup
rm -rf $SNAP_DIR/*
