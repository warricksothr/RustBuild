#!/usr/bin/env bash

# I run this in Debian Jessie container with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     systemd-nspawn /chroot/RustBuild/ /bin/bash ~/build-cargo.sh

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
# Determine if we need to build cargo with a nightly cargo or not
: ${BUILD_WITH_NIGHTLY_CARGO:=false}

# Rust directories
: ${CARGO_NIGHTLY_DIR:=$NIGHTLY_DIR/cargo}
: ${RUST_NIGHTLY_DIR:=$NIGHTLY_DIR/rust}
: ${CARGO_BETA_DIR:=$BETA_DIR/cargo}
: ${RUST_BETA_DIR:=$BETA_DIR/rust}
: ${CARGO_STABLE_DIR:=$STABLE_DIR/cargo}
: ${RUST_STABLE_DIR:=$STABLE_DIR/rust}

# Determine our appropriate dropbox directories
: ${NIGHTLY_DROPBOX_DIR:=.}
: ${BETA_DROPBOX_DIR:=$($DROPBOX list . | grep -F [D] | grep beta | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)/}
: ${STABLE_DROPBOX_DIR:=$($DROPBOX list . | grep -F [D] | grep stable | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)/}

# The default build directories
: ${RUST_DIST_DIR:=$RUST_NIGHTLY_DIR}
: ${CARGO_DIST_DIR:=$CARGO_NIGHTLY_DIR}
: ${DROPBOX_DIR=$NIGHTLY_DROPBOX_DIR}

# Set the channel
if [ ! -z $1 ]; then
  CHANNEL=$1
fi

# Set the descriptor to be used in the build name
: ${CHANNEL_DESCRIPTOR:=${DESCRIPTOR}-}

# Configure the build
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

start=$(date +"%s")

# update source to match upstream
cd $SRC_DIR
git checkout .
git checkout master
git pull
git submodule update

#Parse the version from the cargo config file
VERSION=$(cat Cargo.toml | grep version | head -n 1 | sed -e "s/.*= //" | sed 's/"//g')

# apply patch to link statically against libssl
git apply /build/patches/static-ssl.patch

# get information about HEAD
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=cargo-$VERSION-$CHANNEL-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=cargo-$VERSION-$CHANNEL-$HEAD_DATE-$HEAD_HASH.test.output.txt
LOGFILE_FAILED=cargo--$VERSION-$CHANNEL-$HEAD_DATE-$HEAD_HASH.test.failed.output.txt

# check if we have build this exact version of cargo
if [ ! -z "$($DROPBOX list $DROPBOX_DIR | grep $HEAD_DATE-$HEAD_HASH)" ]; then
  echo "This version: $HEAD_DATE-$HEAD_HASH of cargo has already been built."
  exit 0
fi

CARGO_DIST=$($DROPBOX list $DROPBOX_DIR | grep cargo- | grep -F .tar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
# It's possible we might not have a already built stable/beta cargo... So we 
# can use a nightly to boostrap the process. Ideally in the future we should
# only fall back on a nightly when we can't get an older stable cargo first.
# Also, this code still doesn't handle when we have a cargo that won't build
# our desired cargo version.
if [ -z "$CARGO_DIST" ]; then
  # Falling back on nightly instead
  CARGO_DIST=$($DROPBOX list . | grep cargo- | grep -F .tar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
  CARGO_DIST_DIR=$CARGO_NIGHTLY_DIR
  BUILD_WITH_NIGHTLY_CARGO=true
fi
# Clean the cargo directory (if necessary)
cd $CARGO_DIST_DIR

# Get info about the currently installed version
INSTALLED_CARGO_VERSION=$(cat VERSION)
if [ "$CARGO_DIST" != "$INSTALLED_CARGO_VERSION" ]; then
  rm -rf *
  CARGO_DIST_PATH=$CARGO_DIST
  if [ $BUILD_WITH_NIGHTLY_CARGO -eq 1 && "$DROPBOX_DIR" != "." ]; then
    CARGO_DIST_PATH="${DROPBOX_DIR}${CARGO_DIST}"
  fi
  # download the latest and deploy it
  $DROPBOX -p download $CARGO_DIST_PATH
  tar xzf $CARGO_DIST
  rm $CARGO_DIST
  echo "$CARGO_DIST" > VERSION
else
  echo "Installed Cargo version $INSTALLED_CARGO_VERSION matches the requested Cargo version $CARGO_DIST. No need to re-download our existing install."
fi

export LD_LIBRARY_PATH="$LIBSSL_DIST_DIR/lib:$RUST_DIST_DIR/lib:$CARGO_DIST_DIR/lib:LD_LIBRARY_PATH"

# cargo doesn't always build with my latest rust version, so try all the
# versions available. Theoretically stable/beta rusts should build cargo
# with no issues. Nightlies may have issues though, so this is here!
# FIXME the right way to do this would use the date in the src/rustversion.txt
# file
for RUST_DIST in $($DROPBOX list $DROPBOX_DIR | grep rust- | grep -F .tar | tr -s ' ' | cut -d ' ' -f 4 | sort -r); do
  ## install rust dist
  cd $RUST_DIST_DIR
  
  # Get info about the currentl installed Rust distribution
  INSTALLED_RUST_VERSION=$(cat VERSION)
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

  ## test rust and cargo nightlies
  $RUST_DIST_DIR/bin/rustc -V
  PATH="$PATH:$RUST_DIST_DIR/bin" $CARGO_DIST_DIR/bin/cargo -V

  ## build it, if compilation fails try the next nightly
  cd $SRC_DIR
  
  # Clean previous cargo builds
  PATH="$PATH:$RUST_DIST_DIR/bin" $CARGO_DIST_DIR/bin/cargo clean
  
  # Update the cargo dependencies
  #PATH="$PATH:$RUST_DIST_DIR/bin" $CARGO_DIST_DIR/bin/cargo update

  ./configure \
    --disable-verify-install \
    --enable-nightly \
    --enable-optimize \
    --local-cargo=$CARGO_DIST_DIR/bin/cargo \
    --local-rust-root=$RUST_DIST_DIR \
    --prefix=/
  make clean
  make || continue

  ## package
  rm -rf $DIST_DIR/*
  DESTDIR=$DIST_DIR make install
  cd $DIST_DIR
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

  # delete older cargo versions
  NUMBER_OF_CARGO_BUILDS=$($DROPBOX list $DROPBOX_DIR | grep cargo- | grep -F .tar | wc -l)
  for i in $(seq `expr $MAX_NUMBER_OF_CARGO_BUILDS + 1` $NUMBER_OF_CARGO_BUILDS); do
    OLDEST_CARGO=$($DROPBOX list $DROPBOX_DIR | grep cargo- | grep -F .tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
    OLDEST_TEST_OUTPUT=$(echo $OLDEST_CARGO | cut -d '-' -f 1-5).test.output.txt
    OLDEST_TEST_FAILED_OUTPUT=$(echo $OLDEST_CARGO | cut -d '-' -f 1-5).test.failed.output.txt
    OLDEST_CARGO_PATH=$OLDEST_CARGO
    OLDEST_TEST_OUTPUT_PATH=$OLDEST_TEST_OUTPUT
    OLDEST_TEST_FAILED_OUTPUT_PATH=$OLDEST_TEST_FAILED_OUTPUT
    if [ "$DROPBOX_DIR" != "." ]; then
      OLDEST_CARGO_PATH="${DROPBOX_DIR}${OLDEST_CARGO}"
      OLDEST_TEST_OUTPUT_PATH=${DROPBOX_DIR}$OLDEST_TEST_OUTPUT
      OLDEST_TEST_FAILED_OUTPUT_PATH=${DROPBOX_DIR}$OLDEST_TEST_FAILED_OUTPUT
    fi
    $DROPBOX delete $OLDEST_CARGO_PATH
    $DROPBOX delete $OLDEST_TEST_OUTPUT_PATH || true
    $DROPBOX delete $OLDEST_TEST_FAILED_OUTPUT_PATH || true
  done

  end=$(date +"%s")
  diff=$(($end-$start))
  echo "Cargo Build Time: $(($diff / 3600)) hours, $((($diff / 60) % 60)) minutes and $(($diff % 60)) seconds elapsed."
  starttest=$(date +"%s")

  # run tests
  if [ -z $DONTTEST ]; then
    cd $SRC_DIR
    uname -a > $LOGFILE
    uname -a > $LOGFILE_FAILED
    $RUST_DIST_DIR/bin/rustc -V >> $LOGFILE
    $RUST_DIST_DIR/bin/rustc -V >> $LOGFILE_FAILED
    echo >> $LOGFILE
    echo >> $LOGFILE_FAILED
    RUST_TEST_THREADS=$(nproc) make test -k >>$LOGFILE 2>&1 || true
    cat $LOGFILE | grep "FAILED" >> $LOGFILE_FAILED
    $DROPBOX -p upload $LOGFILE $DROPBOX_DIR
    $DROPBOX -p upload $LOGFILE_FAILED $DROPBOX_DIR
    rm $LOGFILE $LOGFILE_FAILED
  fi

  # cleanup
  #rm -rf $CARGO_DIST_DIR/*
  rm -rf $DIST_DIR/*

  end=$(date +"%s")
  diff=$(($end-$starttest))
  echo "Cargo Test Time: $(($diff / 3600)) hours, $((($diff / 60) % 60)) minutes and $(($diff % 60)) seconds elapsed."
  diff=$(($end-$start))
  echo "Cargo Total Time: $(($diff / 3600)) hours, $((($diff / 60) % 60)) minutes and $(($diff % 60)) seconds elapsed."

  exit 0
done

exit 1
