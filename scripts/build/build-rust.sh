#!/usr/bin/env bash

# I run this in Debian Jessie container with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     systemd-nspawn /chroot/RustBuild/ /bin/bash ~/build-rust.sh

#
# Builds the rust compiler with a previously built snapshot for the target
#

set -x
set -e

# Source the tools script
. $HOME/tools.sh

: ${CHANNEL:=nightly}
: ${DESCRIPTOR:=nightly}
: ${BRANCH:=master}
: ${DIST_DIR:=~/dist}
: ${DROPBOX:=~/dropbox_uploader_cache_proxy.sh}
: ${DROPBOX_SAVE_ROOT:=${CONTAINER_TAG}/}
: ${MAX_NUMBER_OF_BUILDS:=10}
: ${SNAP_DIR:=/build/snapshot}
: ${SRC_DIR:=/build/rust}
# The number of process we should use while building
: ${BUILD_PROCS:=$(($(nproc)-1))}

# These are defaults that can be overwritten by a container build configuration file
: ${USE_CLANG:=true}

# Source additional global variables if available
if [ -f ~/BUILD_CONFIGURATION ]; then
  . ~/BUILD_CONFIGURATION
fi

# Set the build procs to 1 less than the number of cores/processors available,
# but always atleast 1 if there's only one processor/core
if [ ! $BUILD_PROCS -gt 1 ]; then BUILD_PROCS=1; fi

echo "GLIBC Version Info: $(dpkg -l | grep libc6 | head -n1 | tr -s ' ' | cut -d ' ' -f 2-4)"
echo "LDD Version Info: $(ldd --version | head -n 1)"
echo "Linker Version Info: $(ld --version | head -n 1)"

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

# Set the channel
if [ ! -z $1 ]; then
  CHANNEL=$1
  DESCRIPTOR=$1
fi

# Configure the build
case $CHANNEL in
  stable)
    CHANNEL=--release-channel=$CHANNEL
    BRANCH=stable
  ;;
  beta)
    CHANNEL=--release-channel=$CHANNEL
    BRANCH=beta
  ;;
  nightly) 
    CHANNEL=
  ;;
  tag-*)
    # Allow custom branches to be requested
    BRANCH=$(echo $CHANNEL |  $(sed 's/tag-//') .
    CHANNEL=
  ;;
  *) 
    echo "unknown release channel: $CHANNEL" && exit 1
  ;;
esac

start_time="$(date +%s)"

# Update source to upstream
cd $SRC_DIR
git remote update
git clean -df
git checkout -- .
git checkout $BRANCH
git submodule update
git reset --hard origin/$BRANCH
git submodule update
git pull
git submodule update

#Parse the version from the make file
VERSION=$(cat mk/main.mk | grep CFG_RELEASE_NUM | head -n 1 | sed -e "s/.*=//")

#Apply the patch that allows us to specify a custom LLVM_TARGETS variable
git apply /build/patches/rust_configure_llvm_targets.patch

case $DESCRIPTOR in
  stable | beta )
    DROPBOX_SAVE_ROOT="${CONTAINER_TAG}/${VERSION}-${DESCRIPTOR}/"
  ;;
  nightly | tag-*)
  ;;
  *) 
    echo "unknown release channel: $DESCRIPTOR" && exit 1
  ;;
esac

# Get the hash and date of the latest snaphot
SNAP_HASH=$(head -n 1 src/snapshots.txt | tr -s ' ' | cut -d ' ' -f 3)

# Check if the snapshot is available
SNAP_TARBALL=$($DROPBOX list ${CONTAINER_TAG}/snapshots | grep $SNAP_HASH | grep -F .tar)
if [ -z "$SNAP_TARBALL" ]; then
  exit 1
fi
SNAP_TARBALL=$(echo $SNAP_TARBALL | tr -s ' ' | cut -d ' ' -f 3)

# setup snapshot
cd $SNAP_DIR
# Only need to download if our current snapshot is not at the right version
INSTALLED_SNAPSHOT_VERSION=
if [ -f VERSION ]; then
  INSTALLED_SNAPSHOT_VERSION=$(cat VERSION)
fi
if [ "$SNAP_TARBALL" != "$INSTALLED_SNAPSHOT_VERSION" ]; then
  rm -rf *
  $DROPBOX -p download ${CONTAINER_TAG}/snapshots/$SNAP_TARBALL
  tar xjf $SNAP_TARBALL --strip-components=1
  rm $SNAP_TARBALL
  echo "$SNAP_TARBALL" > VERSION
else
  echo "Requested snapshot $SNAP_TARBALL already installed, no need to re-download and install."
fi
bin/rustc -V

# Get information about HEAD
cd $SRC_DIR
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=rust-$VERSION-${DESCRIPTOR}-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=rust-$VERSION-${DESCRIPTOR}-$HEAD_DATE-$HEAD_HASH.test.output.txt
LOGFILE_FAILED=rust-$VERSION-${DESCRIPTOR}-$HEAD_DATE-$HEAD_HASH.test.failed.output.txt

# Check to see if we've already built one
# If so, skip this build and call it good!
if [ ! -z "$($DROPBOX list $DROPBOX_SAVE_ROOT | grep $HEAD_DATE-$HEAD_HASH)" ]; then
  echo "We've already built this version. Skipping!"
  exit 0
fi

# build it
cd build

# Here we do some additional important cleanup
if [ -d arm-unknown-linux-gnueabihf ]; then
  rm -rf arm-unknown-linux-gnueabihf
fi

# Override the LLVM build targets. only need arm.
LLVM_TARGETS=arm ../configure \
  $CHANNEL \
  --disable-valgrind \
  --enable-ccache \
  $CLANG_PARAMS \
  --enable-local-rust \
  --enable-llvm-static-stdcpp \
  --local-rust-root=$SNAP_DIR \
  --prefix=/ \
  --build=arm-unknown-linux-gnueabihf \
  --host=arm-unknown-linux-gnueabihf \
  --target=arm-unknown-linux-gnueabihf
make clean
make -j $BUILD_PROCS

# package
rm -rf $DIST_DIR/*
DESTDIR=$DIST_DIR make -j $BUILD_PROCS install
cd $DIST_DIR
tar czf ~/$TARBALL .
cd ~
TARBALL_HASH=$(sha1sum $TARBALL | tr -s ' ' | cut -d ' ' -f 1)
mv $TARBALL $TARBALL-$TARBALL_HASH.tar.gz
TARBALL=$TARBALL-$TARBALL_HASH.tar.gz

# ship it
if [ -z $DONTSHIP ]; then
  # Try and create the directory if this is not a nightly
  if [ "$DESCRIPTOR" != "nightly" ]; then
    $DROPBOX mkdir ${DROPBOX_SAVE_ROOT}
  fi
  $DROPBOX -p upload $TARBALL ${DROPBOX_SAVE_ROOT}
fi
rm $TARBALL

# Tweet that we've built a new rustc version
tweet_status "Successfully Built: ${CONTAINER_TAG} Rust-${VERSION}-${DESCRIPTOR} #RustBuild"

# delete older nightlies
NUMBER_OF_BUILDS=$($DROPBOX list $DROPBOX_SAVE_ROOT | grep rust- | grep -F .tar | wc -l)
for i in $(seq `expr $MAX_NUMBER_OF_BUILDS + 1` $NUMBER_OF_BUILDS); do
  OLDEST_BUILD=$($DROPBOX list $DROPBOX_SAVE_ROOT | grep rust- | grep -F .tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_BUILD}
  OLDEST_TEST_OUTPUT=$(echo $OLDEST_BUILD | cut -d '-' -f 1-7).test.output.txt
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_TEST_OUTPUT} || true
  OLDEST_TEST_FAILED_OUTPUT=$(echo $OLDEST_BUILD | cut -d '-' -f 1-7).test.failed.output.txt
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_TEST_FAILED_OUTPUT} || true
done

compile_end="$(date +%s)"
compile_time=$(($compile_end-$start_time))
# Prints Hours:Minutes:Seconds
printf "Elapsed Rust Compile Time: %02d:%02d:%02d\n" "$((compile_time/3600%24))" "$((compile_time/60%60))" "$((compile_time%60))"
start_test_time="$(date +%s)"

# run tests
if [ -z $DONTTEST ]; then
  cd $SRC_DIR/build
  uname -a > $LOGFILE
  echo >> $LOGFILE
  cat $LOGFILE > $LOGFILE_FAILED
  # Run the tests with x threads, use the timeout util to prevent running more than 120 minutes
  RUST_TEST_THREADS=$BUILD_PROCS timeout 7200 make check -k >>$LOGFILE 2>&1 || true
  cat $LOGFILE | grep "FAILED" >> $LOGFILE_FAILED
  $DROPBOX -p upload $LOGFILE ${DROPBOX_SAVE_ROOT}
  $DROPBOX -p upload $LOGFILE_FAILED ${DROPBOX_SAVE_ROOT}
  rm $LOGFILE $LOGFILE_FAILED
fi

# cleanup
rm -rf $DIST_DIR/*

end_time="$(date +%s)"
test_time=$(($end_time-$start_test_time))
printf "Elapsed Rust Test Time: %02d:%02d:%02d\n" "$((test_time/3600%24))" "$((test_time/60%60))" "$((test_time%60))"
running_time=$(($end_time-$start_time))
printf "Elapsed Rust Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"
