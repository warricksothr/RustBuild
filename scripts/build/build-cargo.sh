#!/bin/bash

# I run this in Raspbian chroot with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM chroot \
#     /chroot/raspbian/cargo /ruststrap/armhf/build-cargo.sh

set -x
set -e

: ${DIST_DIR:=~/dist}
: ${DROPBOX:=~/dropbox_uploader.sh}
: ${MAX_NUMBER_OF_NIGHTLIES:=5}
: ${NIGHTLY_DIR:=/build/nightly}
: ${SRC_DIR:=/build/cargo}
: ${LIBSSL_DIST_DIR:=/build/openssl/dist}

CARGO_NIGHTLY_DIR=$NIGHTLY_DIR/cargo
RUST_NIGHTLY_DIR=$NIGHTLY_DIR/rust

# update source to match upstream
cd $SRC_DIR
git checkout .
git checkout master
git pull

# optionally checkout older commit
git checkout $1
git submodule update

# apply patch to link statically against libssl
git apply /build/static-ssl.patch

# get information about HEAD
HEAD_HASH=$(git rev-parse --short HEAD)
HEAD_DATE=$(TZ=UTC date -d @$(git show -s --format=%ct HEAD) +'%Y-%m-%d')
TARBALL=cargo-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=cargo-$HEAD_DATE-$HEAD_HASH.test.output.txt

# check if we have build this exact version of cargo
if [ ! -z "$($DROPBOX list | grep $HEAD_DATE-$HEAD_HASH)" ]; then
  exit 0
fi

# XXX It's possible that cargo won't build with the latest cargo nightly, so
# I should try all the available nightlies. However, I haven't seen that
# happen in practice yet, so I'll just try the latest cargo nightly for now
# install cargo nightly
cd $CARGO_NIGHTLY_DIR
rm -rf *
CARGO_NIGHTLY=$($DROPBOX list . | grep cargo- | grep tar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
$DROPBOX -p download $CARGO_NIGHTLY
tar xzf $CARGO_NIGHTLY
rm $CARGO_NIGHTLY

export LD_LIBRARY_PATH="$LIBSSL_DIST_DIR/lib:$LD_LIBRARY_PATH:$RUST_NIGHTLY_DIR/lib:$CARGO_NIGHTLY_DIR/lib"
# Attempt to fix Position-Independent-Code
#export CFLAGS="$CFLAGS -fPIC"
#export OPENSSL_LIB_DIR="$LIBSSL_DIST_DIR/lib"
#export OPENSSL_INCLUDE_DIR="$LIBSSL_DIST_DIR/include"
#export OPENSSL_STATIC=yes

# cargo doesn't always build with my latest rust nightly, so try all the
# nightlies available.
# FIXME the right way to do this would use the date in the src/rustversion.txt
# file
for RUST_NIGHTLY in $($DROPBOX list . | grep rust- | grep tar | tr -s ' ' | cut -d ' ' -f 4 | sort -r); do
  ## install nigthly rust
  cd $RUST_NIGHTLY_DIR
  rm -rf *
  $DROPBOX -p download $RUST_NIGHTLY
  tar xzf $RUST_NIGHTLY
  rm $RUST_NIGHTLY

  ## test rust and cargo nightlies
  $RUST_NIGHTLY_DIR/bin/rustc -V
  PATH="$PATH:$RUST_NIGHTLY_DIR/bin" $CARGO_NIGHTLY_DIR/bin/cargo -V

  ## build it, if compilation fails try the next nightly
  cd $SRC_DIR
  
  # Clean previous cargo builds
  PATH="$PATH:$RUST_NIGHTLY_DIR/bin" $CARGO_NIGHTLY_DIR/bin/cargo clean
  
  # Update the cargo dependencies
  #PATH="$PATH:$RUST_NIGHTLY_DIR/bin" $CARGO_NIGHTLY_DIR/bin/cargo update

  ./configure \
    --disable-verify-install \
    --enable-nightly \
    --enable-optimize \
    --local-cargo=$CARGO_NIGHTLY_DIR/bin/cargo \
    --local-rust-root=$RUST_NIGHTLY_DIR \
    --prefix=/
  make clean
  #OPENSSL_LIB_DIR="$LIBSSL_DIST_DIR/lib" OPENSSL_INCLUDE_DIR="$LIBSSL_DIST_DIR/include" OPENSSL_STATIC=yes make || continue
  make || continue

  ## package
  rm -rf $DIST_DIR/*
  DESTDIR=$DIST_DIR make install
  cd $DIST_DIR
  # smoke test the produced cargo nightly
  PATH=$PATH:$RUST_NIGHTLY_DIR/bin LD_LIBRARY_PATH=$LD_LIBRARY_PATH:lib bin/cargo -V
  tar czf ~/$TARBALL .
  cd ~
  TARBALL_HASH=$(sha1sum $TARBALL | tr -s ' ' | cut -d ' ' -f 1)
  mv $TARBALL $TARBALL-$TARBALL_HASH.tar.gz
  TARBALL=$TARBALL-$TARBALL_HASH.tar.gz

  # ship it
  if [ -z $DONTSHIP ]; then
    $DROPBOX -p upload $TARBALL .
  fi
  rm $TARBALL

  # delete older nightlies
  NUMBER_OF_NIGHTLIES=$($DROPBOX list . | grep cargo- | grep tar | wc -l)
  for i in $(seq `expr $MAX_NUMBER_OF_NIGHTLIES + 1` $NUMBER_OF_NIGHTLIES); do
    OLDEST_NIGHTLY=$($DROPBOX list . | grep cargo- | grep tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
    $DROPBOX delete $OLDEST_NIGHTLY
    OLDEST_TEST_OUTPUT=$(echo $OLDEST_NIGHTLY | cut -d '-' -f 1-5).test.output.txt
    $DROPBOX delete $OLDEST_TEST_OUTPUT || true
  done

  # run tests
  if [ -z $DONTTEST ]; then
    cd $SRC_DIR
    uname -a > $LOGFILE
    $RUST_NIGHTLY_DIR/bin/rustc -V >> $LOGFILE
    echo >> $LOGFILE
    RUST_TEST_THREADS=$(nproc) make test -k >>$LOGFILE 2>&1 || true
    $DROPBOX -p upload $LOGFILE .
    rm $LOGFILE
  fi

  # cleanup
  rm -rf $CARGO_NIGHTLY_DIR/*
  rm -rf $DIST_DIR/*
  rm -rf $RUST_NIGHTLY_DIR/*

  exit 0
done

exit 1
