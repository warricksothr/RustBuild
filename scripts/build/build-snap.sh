#!/usr/bin/env bash

# I run this in Debian Jessie container with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     systemd-nspawn /chroot/RustBuild/ /bin/bash ~/build-snap.sh

#
# This script will build a snapshot for a given rust branch, either based on
# the tag, or the following branches (stable,beta,master)
#
# The goal of this script is to compile a standalone static snapshot the rust
# compiler, to be used in the creation of full rust compilers and standard
# libraries. This is the first step in the process of creating a rust compiler
# from scratch. It depends on a previous compiler existing for the 
# architecture. If one does not exist, then you'll need to cross compile a
# snapshot build for the desired architecture.
#

#set -x
set -e

# Source the tools script
. $HOME/tools.sh

: ${CHANNEL:=nightly}
: ${BRANCH:=master}
: ${DROPBOX:=~/dropbox_uploader_cache_proxy.sh}
: ${SNAP_DIR:=/build/snapshot}
: ${SRC_DIR:=/build/rust}
# Determines if we can't get the second to last snapshot, if we should try with
# the oldest, or just fail. We default to true because we always want to try to
# build a snapshot
: ${FAIL_TO_OLDEST_SNAP:=true}
# The number of process we should use while building. Set to the number of
# processors available to the system, - 1.
: ${BUILD_PROCS:=$(($(nproc)-1))}

# These are defaults that can be overwritten by a container build configuration file
: ${USE_CLANG:=true}

# Source additional global variables if available
if [ -f/ ~/BUILD_CONFIGURATION ]; then
  . ~/BUILD_CONFIGURATION
fi

PRINT_TARGET="&1"
if [ -n "$DEBUG" ]; then
	PRINT_TARGET="/dev/null"
fi

# Set the channel
if [ ! -z $1 ]; then
  CHANNEL=$1
fi

# Configure the build
# Determine the branch that we'll use to build the snapshot
case $CHANNEL in
  stable)
    BRANCH=stable
  ;;
  beta)
    BRANCH=beta
  ;;
  nightly);;
  tag-*)
    # Allow custom branches to be requested
    BRANCH=$(echo $CHANNEL | $(sed 's/tag-//') .
  ;;
  *) 
    echo "unknown release channel: $CHANNEL" && exit 1
  ;;
esac

# Set the build procs to 1 less than the number of cores/processors available,
# but always atleast 1 if there's only one processor/core
if [ ! $BUILD_PROCS -gt 1 ]; then BUILD_PROCS=1; fi

#Make sure we're using the correct tag for this container
if [ -z $CONTAINER_TAG ]; then
  if [ -f "${HOME}/CONTAINER_TAG" ]; then
    export CONTAINER_TAG="$(cat ${HOME}/CONTAINER_TAG)"
  fi
fi

# Set The Clang Parameters
if $USE_CLANG; then
: ${CLANG_PARAMS:="--enable-clang --disable-libcpp"}
else
: ${CLANG_PARAMS:=}
fi

echo "####################################################################"
echo "# Building Rust Snapshot For [$CONTAINER_TAG] On Branch [$CHANNEL] #"
echo "####################################################################"

echo "GLIBC Version Info: $(dpkg -l | grep libc6 | head -n1 | tr -s ' ' | cut -d ' ' -f 2-4)"
echo "LDD Version Info: $(ldd --version | head -n 1)"
echo "Linker Version Info: $(ld --version | head -n 1)"

# Number of seconds since unix epoch, to use for documenting the time spent
# building the snapshot
start_time="$(date +%s)"

# checkout the latest for the requested rust $BRANCH
echo "cd $SRC_DIR"
cd $SRC_DIR

echo "Updating Git repository" 
git remote update >$PRINT_TARGET
git clean -df >$PRINT_TARGET
git checkout -- . >$PRINT_TARGET
git checkout $BRANCH >$PRINT_TARGET
git submodule update >$PRINT_TARGET
git reset --hard origin/$BRANCH >$PRINT_TARGET
git submodule update >$PRINT_TARGET
git pull >$PRINT_TARGET
git submodule update >$PRINT_TARGET

# As of Rust 1.10 snapshots are no longer used
# instead the latest stable release is used to build
# so exit here if src/snapshots.txt no longer exists in the repo
if [ ! -f "src/snapshots.txt" ]; then
	echo "Building a release that no longer needs snapshots."
	echo "Exiting gracefully"
	exit 0
fi

# Check if the latest snapshot has already been built
LAST_SNAP_HASH=$(head src/snapshots.txt | head -n 1 | tr -s ' ' | cut -d ' ' -f 3)
if [ ! -z "$($DROPBOX list ${CONTAINER_TAG}/snapshots | grep $LAST_SNAP_HASH)" ]; then
  # already there, nothing left to do
  echo "Latest snapshot already exists: $LAST_SNAP_HASH"
  exit 0
fi

# This is the second to last snapshot. This is the snapshot that should be used to build the next one
SECOND_TO_LAST_SNAP_HASH=$(cat src/snapshots.txt | grep "S " | sed -n 2p | tr -s ' ' | cut -d ' ' -f 3)
SNAP_TARBALL="$($DROPBOX list ${CONTAINER_TAG}/snapshots | grep $SECOND_TO_LAST_SNAP_HASH | tr -s ' ' | cut -d ' ' -f 4)"
if [ -z "$($DROPBOX list ${CONTAINER_TAG}/snapshots | grep $SECOND_TO_LAST_SNAP_HASH)" ]; then
  if $FAIL_TO_OLDEST_SNAP; then
    #all_snaps_available=($("$DROPBOX list ${CONTAINER_TAG}/snapshots | tr -s ' ' cut -d ' ' -f 4)")
    snap_count=$(cat src/snapshots.txt | grep "S " | wc -l)
    for ((pos=3; pos<=$snap_count; pos++)); do
      SECOND_TO_LAST_SNAP_HASH=$(cat src/snapshots.txt | grep "S " | sed -n ${pos}p | tr -s ' ' | cut -d ' ' -f 3)
      SNAP_TARBALL="$($DROPBOX list ${CONTAINER_TAG}/snapshots | grep $SECOND_TO_LAST_SNAP_HASH | tr -s ' ' | cut -d ' ' -f 4)"
      if [ -z $SNAP_TARBALL ]; then
        if [ $pos -eq $snap_count ]; then
          echo "No snapshot older than  ${LAST_SNAP_HASH} available. Need an older snapshot to build a current snapshot"
          exit 1
        else
          continue
        fi
      else
        break
      fi
    done
  else
    # not here, we need this snapshot to continue
    echo "Need snapshot ${SECOND_TO_LAST_SNAP_HASH} to compile snapshot compiler ${LAST_SNAP_HASH}"
    exit 1
  fi
fi

# Use the second to last snapshot to build the next snapshot setup snapshot
cd $SNAP_DIR
# Only need to download if our current snapshot is not at the right version
INSTALLED_SNAPSHOT_VERSION=
if [ -f VERSION ]; then
  INSTALLED_SNAPSHOT_VERSION=$(cat VERSION)
fi
if [ "$SNAP_TARBALL" != "$INSTALLED_SNAPSHOT_VERSION" ]; then
  rm -rf *
  SNAP_TARBALL=$($DROPBOX list ${CONTAINER_TAG}/snapshots | grep ${SECOND_TO_LAST_SNAP_HASH}- | tr -s ' ' | cut -d ' ' -f 4)
  $DROPBOX -p download ${CONTAINER_TAG}/snapshots/$SNAP_TARBALL
  tar xjf $SNAP_TARBALL --strip-components=1
  rm $SNAP_TARBALL
  echo "$SNAP_TARBALL" > VERSION
else
  echo "Requested snapshot $SNAP_TARBALL already installed, no need to re-download and install."
fi

# build the snapshot
# --disable-docs to prevent documentation from being built
# --disable-valgrind to prevent testing with valgrind
# --enable-ccache to speed up the build by using a code cache
# --enable-clang to use the clang compiler instead of gcc/g++
# --disable-libcpp to instead use libstdc++ instead for clang
# --enable-local-rust to use a prebuilt snapshot, instead of trying to download one
# --enable-llvm-static-stdcpp ?
# --local-rust/root=? this is where the local rust we said to use is located
# --prefix=/ to prevent installing this to the system
# --build=? the triple that represents the our build system?
# --host=? the triple that represents our build system
# --target=? the triple that represents the target system. Used for cross compiling
cd $SRC_DIR
git checkout $LAST_SNAP_HASH >$PRINT_TARGET
cd build
../configure \
  --disable-docs \
  --disable-valgrind \
  --enable-ccache \
  $CLANG_PARAMS \
  --enable-local-rust \
  --enable-llvm-static-stdcpp \
  --local-rust-root=$SNAP_DIR \
  --prefix=/ \
  --build=arm-unknown-linux-gnueabihf \
  --host=arm-unknown-linux-gnueabihf \
  --target=arm-unknown-linux-gnueabihf >$PRINT_TARGET
# Clean any previous builds
make clean >$PRINT_TARGET
# Actually build the full rust compiler
make -j $BUILD_PROCS >$PRINT_TARGET
# Create a static snapshot version for host triple
make -j $BUILD_PROCS snap-stage3-H-arm-unknown-linux-gnueabihf >$PRINT_TARGET

# ship it
$DROPBOX -p upload rust-stage0-* ${CONTAINER_TAG}/snapshots
rm rust-stage0-*

# cleanup
#rm -rf $SNAP_DIR/*

end_time="$(date +%s)"
running_time=$(($end_time-$start_time))
# Prints Hours:Minutes:Seconds
printf "Elapsed Snapshot Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"

echo "#########################################################################"
echo "# Done Building Rust Snapshot For [$CONTAINER_TAG] On Branch [$CHANNEL] #"
echo "#########################################################################"
echo ""
