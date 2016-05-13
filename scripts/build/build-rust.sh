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

#set -x
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
: ${LLVM_BUILD_ROOT:=/build/llvm_build}
# The number of process we should use while building
: ${BUILD_PROCS:=$(($(nproc)-1))}

# These are defaults that can be overwritten by a container build configuration file
: ${USE_CLANG:=true}

# Source additional global variables if available
if [ -f ~/BUILD_CONFIGURATION ]; then
  . ~/BUILD_CONFIGURATION
fi

PRINT_TARGET=
if [ -z "$DEBUG" ]; then
  echo "Debugging Off"
  PRINT_TARGET="> /dev/null"
fi

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

echo "############################################################################"
echo "# Building Rustc and Rust stdlib For [$CONTAINER_TAG] On Branch [$CHANNEL] #"
echo "############################################################################"

echo "GLIBC Version Info: $(dpkg -l | grep libc6 | head -n1 | tr -s ' ' | cut -d ' ' -f 2-4)"
echo "LDD Version Info: $(ldd --version | head -n 1)"
echo "Linker Version Info: $(ld --version | head -n 1)"

start_time="$(date +%s)"

# Update source to upstream
echo "cd $SRC_DIR"
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

# Build with armv7 optimizations if that's the container target
# https://github.com/warricksothr/RustBuild/issues/11
CONFIG_BUILD=arm-unknown-linux-gnueabihf
CONFIG_HOST=arm-unknown-linux-gnueabihf
CONFIG_TARGET=arm-unknown-linux-gnueabihf
if [ "$CONTAINER_TAG" = "ARMv7" ]; then
	CONFIG_BUILD=armv7-unknown-linux-gnueabihf
	CONFIG_HOST=armv7-unknown-linux-gnueabihf
	CONFIG_TARGET=armv7-unknown-linux-gnueabihf
fi

#Parse the version from the make file
VERSION=$(cat mk/main.mk | grep CFG_RELEASE_NUM | head -n 1 | sed -e "s/.*=//")

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

# Rust builds as of 1.10 no longer use a snapsot to compile
# if src/snapshots.txt doesn't exist use the latest stable
# to compile instead
if [ ! "src/snapshots.txt" ]; then
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
else
  # If not using a snapshot the following is how we build rust
  # Stable, Beta, Tag => Build with the latest rust stable
  # Nightly =. Build with the latest rust beta
  echo "Not using a snapshot to compile"
  case $DESCRIPTOR in
    stable)
      SNAP_DIR=/opt/rust_stable/rust
    ;;
    beta)
      SNAP_DIR=/opt/rust_stable/rust
    ;;
    nightly) 
      SNAP_DIR=/opt/rust_beta/rust
    ;;
    tag-*)
      SNAP_DIR=/opt/rust_stable/rust
    ;;
    *) 
      echo "unknown release channel: $CHANNEL" && exit 1
    ;;
  esac
fi

# Get information about HEAD
cd $SRC_DIR
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=rust-$VERSION-${DESCRIPTOR}-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
TARBALL_LIB=rustlib-$VERSION-${DESCRIPTOR}-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
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
# Temporarily disabling. The error that was caused shouldn't need cleaning this all the time.
#if [ -d arm-unknown-linux-gnueabihf ]; then
#  rm -rf arm-unknown-linux-gnueabihf
#fi

echo "Configuring Rust Build"
# Override the LLVM build targets. only need arm.
../configure \
  $CHANNEL \
  --disable-jemalloc \
  --disable-valgrind \
  --enable-ccache \
  --llvm-root=$LLVM_BUILD_ROOT \
  $CLANG_PARAMS \
  --enable-local-rust \
  --enable-llvm-static-stdcpp \
  --local-rust-root=$SNAP_DIR \
  --prefix=/ \
  --build=$CONFIG_BUILD \
  --host=$CONFIG_HOST \
  --target=$CONFIG_TARGET
make clean
RUSTFLAGS="-C codegen-units=$BUILD_PROCS" make -j $BUILD_PROCS

# Package rust and rustlib
rm -rf $DIST_DIR/*
DESTDIR=$DIST_DIR make -j $BUILD_PROCS install
cd $DIST_DIR
tar czf ~/$TARBALL .
tar czf ~/$TARBALL_LIB ./lib/rustlib
cd ~

# Add the sha1sum of the file to the name
TARBALL_HASH=$(sha1sum $TARBALL | tr -s ' ' | cut -d ' ' -f 1)
mv $TARBALL $TARBALL-$TARBALL_HASH.tar.gz
TARBALL=$TARBALL-$TARBALL_HASH.tar.gz

# Add the sha1sum of the file to the name
TARBALL_LIB_HASH=$(sha1sum $TARBALL_LIB | tr -s ' ' | cut -d ' ' -f 1)
mv $TARBALL_LIB $TARBALL_LIB-$TARBALL_LIB_HASH.tar.gz
TARBALL_LIB=$TARBALL_LIB-$TARBALL_LIB_HASH.tar.gz

# ship it
if [ -z $DONTSHIP ]; then
  # Try and create the directory if this is not a nightly
  if [ "$DESCRIPTOR" != "nightly" ]; then
    $DROPBOX mkdir ${DROPBOX_SAVE_ROOT}
  fi
  echo "Saving [$TARBALL] and [$TARBALL_LIB] to Dropbox"
  $DROPBOX -p upload $TARBALL ${DROPBOX_SAVE_ROOT}
  $DROPBOX -p upload $TARBALL_LIB ${DROPBOX_SAVE_ROOT}
fi
rm $TARBALL
rm $TARBALL_LIB

# Tweet that we've built a new rustc version
tweet_status "Successfully Built: ${CONTAINER_TAG} Rust-${VERSION}-${DESCRIPTOR} #RustBuild"

# delete older nightlies
echo "Cleaning up number of builds"
NUMBER_OF_BUILDS=$($DROPBOX list $DROPBOX_SAVE_ROOT | grep rust- | grep -F .tar | wc -l)
echo "Found [$NUMBER_OF_BUILDS]/[$MAX_NUMBER_OF_BUILDS]"
for i in $(seq `expr $MAX_NUMBER_OF_BUILDS + 1` $NUMBER_OF_BUILDS); do
  OLDEST_BUILD=$($DROPBOX list $DROPBOX_SAVE_ROOT | grep rust- | grep -F .tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_BUILD}
  OLDEST_TEST_OUTPUT=$(echo $OLDEST_BUILD | cut -d '-' -f 1-7).test.output.txt
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_TEST_OUTPUT} || true
  OLDEST_TEST_FAILED_OUTPUT=$(echo $OLDEST_BUILD | cut -d '-' -f 1-7).test.failed.output.txt
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_TEST_FAILED_OUTPUT} || true
done

NUMBER_OF_BUILDS=$($DROPBOX list $DROPBOX_SAVE_ROOT | grep rustlib- | grep -F .tar | wc -l)
for i in $(seq `expr $MAX_NUMBER_OF_BUILDS + 1` $NUMBER_OF_BUILDS); do
  OLDEST_LIB_BUILD=$($DROPBOX list $DROPBOX_SAVE_ROOT | grep rustlib- | grep -F .tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
  $DROPBOX delete ${DROPBOX_SAVE_ROOT}${OLDEST_LIB_BUILD}
done

compile_end="$(date +%s)"
compile_time=$(($compile_end-$start_time))
# Prints Hours:Minutes:Seconds
printf "Elapsed Rust Compile Time: %02d:%02d:%02d\n" "$((compile_time/3600%24))" "$((compile_time/60%60))" "$((compile_time%60))"
start_test_time="$(date +%s)"

echo "Running Tests"
# run tests
if [ -z $DONTTEST ]; then
  cd $SRC_DIR/build
  uname -a > $LOGFILE
  echo >> $LOGFILE
  cat $LOGFILE > $LOGFILE_FAILED
  # Run the tests with x threads, use the timeout util to prevent running more than 120 minutes
  RUST_TEST_THREADS=$BUILD_PROCS timeout 7200 make check -k >>$LOGFILE 2>&1 || true
  cat $LOGFILE | grep "FAILED" >> $LOGFILE_FAILED
  # Only uploading logs if we're set to upload
  if [ -z $DONTSHIP ]; then
    $DROPBOX -p upload $LOGFILE ${DROPBOX_SAVE_ROOT}
    $DROPBOX -p upload $LOGFILE_FAILED ${DROPBOX_SAVE_ROOT}
  fi
  rm $LOGFILE $LOGFILE_FAILED
fi

# cleanup
rm -rf $DIST_DIR/*

end_time="$(date +%s)"
test_time=$(($end_time-$start_test_time))
printf "Elapsed Rust Test Time: %02d:%02d:%02d\n" "$((test_time/3600%24))" "$((test_time/60%60))" "$((test_time%60))"
running_time=$(($end_time-$start_time))
printf "Elapsed Rust Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"

echo "#################################################################################"
echo "# Done Building Rustc and Rust stdlib For [$CONTAINER_TAG] On Branch [$CHANNEL] #"
echo "#################################################################################"
echo ""
