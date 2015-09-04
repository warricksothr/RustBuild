#!/usr/bin/env bash

# I run this in Debian Jessie container with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     systemd-nspawn /chroot/RustBuild/ /bin/bash ~/build-cargo.sh

#
# Script to build a cargo version as specified by the passed in channel
#

set -x
set -e

: ${DIST_DIR:=~/dist}
: ${DROPBOX:=~/dropbox_uploader_cache_proxy.sh}
: ${MAX_NUMBER_OF_CARGO_BUILDS:=5}
: ${NIGHTLY_DIR:=/opt/rust_nightly}
: ${BETA_DIR:=/opt/rust_beta}
: ${STABLE_DIR:=/opt/rust_stable}
: ${SRC_DIR:=/build/cargo}
: ${LIBSSL_DIST_DIR:=/build/openssl/dist}
: ${CHANNEL:=nightly}

# Rust directories
: ${CARGO_NIGHTLY_DIR:=$NIGHTLY_DIR/cargo}
: ${RUST_NIGHTLY_DIR:=$NIGHTLY_DIR/rust}
: ${CARGO_BETA_DIR:=$BETA_DIR/cargo}
: ${RUST_BETA_DIR:=$BETA_DIR/rust}
: ${CARGO_STABLE_DIR:=$STABLE_DIR/cargo}
: ${RUST_STABLE_DIR:=$STABLE_DIR/rust}

echo "GLIBC Version Info: $(ldd --version | head -n 1)"
echo "Linker Version Info: $(ld --version | head -n 1)"

# Determine our appropriate dropbox directories
# Nightlies are always in the root directory for the container_tag
: ${NIGHTLY_DROPBOX_DIR:=${CONTAINER_TAG}/}
# This returns the newest beta directory
: ${BETA_DROPBOX_DIR:=${CONTAINER_TAG}/$($DROPBOX list ${CONTAINER_TAG}/ | grep -F [D] | grep beta | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)/}
# This returns the newest stable directory
: ${STABLE_DROPBOX_DIR:=${CONTAINER_TAG}/$($DROPBOX list ${CONTAINER_TAG}/ | grep -F [D] | grep stable | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)/}

# The default build directories
: ${RUST_DIST_DIR:=$RUST_NIGHTLY_DIR}
: ${CARGO_DIST_DIR:=$CARGO_NIGHTLY_DIR}
: ${DROPBOX_DIR=$NIGHTLY_DROPBOX_DIR}

#Make sure we're using the correct tag for this container
if [ -z $CONTAINER_TAG ]; then
  if [ -f "${HOME}/CONTAINER_TAG" ]; then
    export CONTAINER_TAG="$(cat ${HOME}/CONTAINER_TAG)"
  fi
fi

# Set the channel if the user supplied one in argument $1
if [ ! -z $1 ]; then
  CHANNEL=$1
fi

# Set the descriptor to be used in the build name
: ${CHANNEL_DESCRIPTOR:=${DESCRIPTOR}-}

# Configure the build
# Set the appropriate distribution directories for rust and cargo
# Set the dropbox output directory and initial check directory
# Halt if a compiler doesn't exist for the channel. This should only happen if
# cargo is attempted to be built before a compiler for the requested channel
# is built
case $CHANNEL in
  stable)
    RUST_DIST_DIR=$RUST_STABLE_DIR
    CARGO_DIST_DIR=$CARGO_STABLE_DIR
    DROPBOX_DIR=$STABLE_DROPBOX_DIR
    if [ -z "$DROPBOX_DIR" ]; then
      echo "Can't build a stable cargo without a stable rust"
      exit 1
    fi
  ;;
  beta)
    RUST_DIST_DIR=$RUST_BETA_DIR
    CARGO_DIST_DIR=$CARGO_BETA_DIR
    DROPBOX_DIR=$BETA_DROPBOX_DIR
    if [ -z "$DROPBOX_DIR" ]; then
      echo "Can't build a beta cargo without a beta rust"
      exit 1
    fi
  ;;
  nightly)
    # Don't need to do anything as these are the defaults
  ;; 
  tag-*)
    # Allow custom branches to be requested
  ;;
  *) 
    echo "unknown release channel: $CHANNEL" && exit 1
  ;;
esac

# Seconds since unix epoch for documentation purposes
start_time="$(date +%s)"

# update source to match upstream
cd $SRC_DIR
git clean -df
git checkout -- .
git checkout master
git pull
git submodule update

# Parse the version from the cargo config file
# Used in the name of the produced packages
VERSION=$(cat Cargo.toml | grep version | head -n 1 | sed -e "s/.*= //" | sed 's/"//g')

# apply patch to link statically against libssl
# This is so that we build cargo with static-ssl, otherwise out distributons
# may fail to run on other systems. This patch is updated so that ideally
# our distributions don't throw warnings on other systems.
git apply /build/patches/static-ssl.patch

# get information about HEAD
# Construct the hash that describes this build
# Construct the paths for the tarball and logs that will be produced
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=cargo-$VERSION-$CHANNEL-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=cargo-$VERSION-$CHANNEL-$HEAD_DATE-$HEAD_HASH.test.output.txt
LOGFILE_FAILED=cargo-$VERSION-$CHANNEL-$HEAD_DATE-$HEAD_HASH.test.failed.output.txt

# check if we have built this exact version of cargo. If so exit gracefully
if [ ! -z "$($DROPBOX list $DROPBOX_DIR | grep $HEAD_DATE-$HEAD_HASH)" ]; then
  echo "This version: $HEAD_DATE-$HEAD_HASH of cargo has already been built."
  exit 0
fi

# Look for the latest built Cargo in the requested channel
CARGO_DIST=$($DROPBOX list $DROPBOX_DIR | grep cargo- | grep -F .tar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
CARGO_DOWNLOAD_PATH=${DROPBOX_DIR}${CARGO_DIST}
# It's possible we might not have a already built stable/beta cargo... So we 
# can use a nightly to boostrap the process. Ideally in the future we should
# only fall back on a nightly when we can't get an older stable cargo first.
# Also, this code still doesn't handle when we have a cargo that won't build
# our desired cargo version.
if [ -z "$CARGO_DIST" ]; then
  # Falling back on nightly instead
  CARGO_DIST=$($DROPBOX list ${NIGHTLY_DROPBOX_DIR} | grep cargo- | grep -F .tar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
  CARGO_DIST_DIR=$CARGO_NIGHTLY_DIR
  # Fall back on the nightly to build with
  CARGO_DOWNLOAD_PATH=${NIGHTLY_DROPBOX_DIR}$CARGO_DIST
fi
# Clean the cargo directory (if necessary)
cd $CARGO_DIST_DIR

# Get info about the currently installed version
# This is here so we can skip redeploying cargo and rust versions that are 
# relatively stable and have few build updates. Mostly saves writing and wear
# on our storage medium and a few seconds of download and deploy time
INSTALLED_CARGO_VERSION=
if [ -f VERSION ]; then
  INSTALLED_CARGO_VERSION=$(cat VERSION)
fi
if [ "$CARGO_DIST" != "$INSTALLED_CARGO_VERSION" ]; then
  rm -rf *
  # download the latest cargo and deploy it
  $DROPBOX -p download $CARGO_DOWNLOAD_PATH
  tar xzf $CARGO_DIST
  rm $CARGO_DIST
  echo "$CARGO_DIST" > VERSION
else
  echo "Installed Cargo version $INSTALLED_CARGO_VERSION matches the requested Cargo version $CARGO_DIST. No need to re-download our existing install."
fi

# This is the library path that determines how we link to libraries
# The latest openssl build on this machine is linked to prevent errors during
# the build about fPIC missing from the libraries.
export LD_LIBRARY_PATH="$LIBSSL_DIST_DIR/lib:$RUST_DIST_DIR/lib:$CARGO_DIST_DIR/lib:LD_LIBRARY_PATH"

# cargo doesn't always build with my latest rust version, so try all the
# versions available. Theoretically stable/beta rusts should build cargo
# with no issues. Nightlies may have issues though, so this is here!
# FIXME the right way to do this would use the date in the src/rustversion.txt
# file
for RUST_DIST in $($DROPBOX list $DROPBOX_DIR | grep rust- | grep -F .tar | tr -s ' ' | cut -d ' ' -f 4 | sort -r); do
  ## install rust dist
  cd $RUST_DIST_DIR
  
  # Get info about the currently installed Rust distribution
  # This is similar to the Cargo process above, and done for the same reasons
  INSTALLED_RUST_VERSION=
  if [ -f VERSION ]; then
    INSTALLED_RUST_VERSION=$(cat VERSION)
  fi
  if [ "$RUST_DIST" != "$INSTALLED_RUST_DIST" ]; then
    rm -rf *
    RUST_DIST_PATH=$RUST_DIST
    if [ "$DROPBOX_DIR" != "." ]; then
       RUST_DIST_PATH="${DROPBOX_DIR}${RUST_DIST}"
    fi
    $DROPBOX -p download $RUST_DIST_PATH
    tar xzf $RUST_DIST
    rm $RUST_DIST
    echo "$RUST_DIST" > VERSION
  else
    echo "Installed Rust version $INSTALLED_RUST_VERSION matches the requested Rust version $RUST_DIST. No need to re-download our existing install."
  fi

  # test rust and cargo nightlies
  # Sanity checks to make sure our binaries are available and work
  $RUST_DIST_DIR/bin/rustc -V
  PATH="$PATH:$RUST_DIST_DIR/bin" $CARGO_DIST_DIR/bin/cargo -V

  # build it, and if compilation fails try the next nightly
  cd $SRC_DIR
  
  # Clean previous cargo builds
  PATH="$PATH:$RUST_DIST_DIR/bin" $CARGO_DIST_DIR/bin/cargo clean
  
  # Update the cargo dependencies
  #PATH="$PATH:$RUST_DIST_DIR/bin" $CARGO_DIST_DIR/bin/cargo update

  # Perform configuration on Cargo
  # --disable-verify-install to prevent checking of the installation post make
  # --enable-nightly to make sure we're using our static ssl builds
  # --enable-optimize to make sure that the produced Cargo is -o2
  # --local-cargo=? local cargo dist to use
  # --local-rust-root=? local rust compiler to use
  # --prefix=/ prevent installation to the default location
  ./configure \
    --disable-verify-install \
    --enable-nightly \
    --enable-optimize \
    --local-cargo=$CARGO_DIST_DIR/bin/cargo \
    --local-rust-root=$RUST_DIST_DIR \
    --prefix=/

  # Clean previous attempts
  make clean
  # Perform the build. If it fails, failover to the next rust compiler
  make || continue 

  # package the distributiable
  rm -rf $DIST_DIR/*
  # Overrides the installation directory
  DESTDIR=$DIST_DIR make install
  cd $DIST_DIR
  # Prove that our built binary atleast links and runs
  # smoke test the produced cargo nightly
  PATH=$PATH:$RUST_DIST_DIR/bin LD_LIBRARY_PATH=$LD_LIBRARY_PATH:lib bin/cargo -V
  tar czf ~/$TARBALL .
  cd ~
  TARBALL_HASH=$(sha1sum $TARBALL | tr -s ' ' | cut -d ' ' -f 1)
  mv $TARBALL $TARBALL-$TARBALL_HASH.tar.gz
  TARBALL=$TARBALL-$TARBALL_HASH.tar.gz

  # ship it
  if [ -z $DONTSHIP ]; then
    $DROPBOX -p upload $TARBALL $DROPBOX_DIR
  fi
  rm $TARBALL

  compile_end="$(date +%s)"
  compile_time=$(($compile_end-$start_time))
  # Prints Hours:Minutes:Seconds
  printf "Elapsed Cargo Compile Time: %02d:%02d:%02d\n" "$((compile_time/3600%24))" "$((compile_time/60%60))" "$((compile_time%60))"
  
  # delete older cargo versions
  # ensure that we only have the max number of cargo builds, delete the oldest
  NUMBER_OF_CARGO_BUILDS=$($DROPBOX list $DROPBOX_DIR | grep cargo- | grep -F .tar | wc -l)
  for i in $(seq `expr $MAX_NUMBER_OF_CARGO_BUILDS + 1` $NUMBER_OF_CARGO_BUILDS); do
    OLDEST_CARGO=$($DROPBOX list $DROPBOX_DIR | grep cargo- | grep -F .tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
    OLDEST_TEST_OUTPUT=$(echo $OLDEST_CARGO | cut -d '-' -f 1-6).test.output.txt
    OLDEST_TEST_FAILED_OUTPUT=$(echo $OLDEST_CARGO | cut -d '-' -f 1-6).test.failed.output.txt
    # Set the paths to the dropbox dir
    OLDEST_CARGO_PATH="${DROPBOX_DIR}${OLDEST_CARGO}"
    OLDEST_TEST_OUTPUT_PATH="${DROPBOX_DIR}${OLDEST_TEST_OUTPUT}"
    OLDEST_TEST_FAILED_OUTPUT_PATH="${DROPBOX_DIR}${OLDEST_TEST_FAILED_OUTPUT}"
    # Delete the oldest
    $DROPBOX delete $OLDEST_CARGO_PATH
    $DROPBOX delete $OLDEST_TEST_OUTPUT_PATH || true
    $DROPBOX delete $OLDEST_TEST_FAILED_OUTPUT_PATH || true
  done

  # Start logging the test time
  start_test_time="$(date +%s)"

  # run the Cargo test suite
  if [ -z $DONTTEST ]; then
    cd $SRC_DIR
    uname -a > $LOGFILE
    $RUST_DIST_DIR/bin/rustc -V >> $LOGFILE
    echo >> $LOGFILE
    cat $LOGFILE > $LOGFILE_FAILED
    RUST_TEST_THREADS=$(nproc) make test -k >>$LOGFILE 2>&1 || true
    cat $LOGFILE | grep "FAILED" >> $LOGFILE_FAILED
    $DROPBOX -p upload $LOGFILE $DROPBOX_DIR
    $DROPBOX -p upload $LOGFILE_FAILED $DROPBOX_DIR
    rm $LOGFILE $LOGFILE_FAILED
  fi

  # cleanup
  rm -rf $DIST_DIR/*

  end_time="$(date +%s)"
  test_time=$(($end_time-$start_test_time))
  printf "Elapsed Cargo Test Time: %02d:%02d:%02d\n" "$((test_time/3600%24))" "$((test_time/60%60))" "$((test_time%60))"
  running_time=$(($end_time-$start_time))
  printf "Elapsed Cargo Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"

  exit 0
done

# If we reached here, then we failed to build Cargo completely!
echo "Failed to build a cargo!"
end_time="$(date +%s)"
running_time=$(($end_time-$start_time))
printf "Elapsed Cargo Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"

exit 1
