#!/bin/bash

# I run this in Debian Jessie container with the following command:
#
# $ env -i \
#     HOME=/root \
#     PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#     SHELL=/bin/bash \
#     TERM=$TERM \
#     systemd-nspawn /chroot/RustBuild/ /bin/bash ~/build-rust.sh

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
TARBALL=cargo-$VERSION-$HEAD_DATE-$HEAD_HASH-arm-unknown-linux-gnueabihf
LOGFILE=cargo-$VERSION-$HEAD_DATE-$HEAD_HASH.test.output.txt
LOGFILE_FAILED=cargo-$VERSION-$HEAD_DATE-$HEAD_HASH.test.failed.output.txt

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
CARGO_NIGHTLY=$($DROPBOX list . | grep cargo- | grep \.tar | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4)
$DROPBOX -p download $CARGO_NIGHTLY
tar xzf $CARGO_NIGHTLY
rm $CARGO_NIGHTLY

export LD_LIBRARY_PATH="$LIBSSL_DIST_DIR/lib:$RUST_NIGHTLY_DIR/lib:$CARGO_NIGHTLY_DIR/lib:LD_LIBRARY_PATH"

# cargo doesn't always build with my latest rust nightly, so try all the
# nightlies available.
# FIXME the right way to do this would use the date in the src/rustversion.txt
# file
for RUST_NIGHTLY in $($DROPBOX list . | grep rust- | grep \.tar | tr -s ' ' | cut -d ' ' -f 4 | sort -r); do
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
  NUMBER_OF_NIGHTLIES=$($DROPBOX list . | grep cargo- | grep \.tar | wc -l)
  for i in $(seq `expr $MAX_NUMBER_OF_NIGHTLIES + 1` $NUMBER_OF_NIGHTLIES); do
    OLDEST_NIGHTLY=$($DROPBOX list . | grep cargo- | grep \.tar | head -n 1 | tr -s ' ' | cut -d ' ' -f 4)
    $DROPBOX delete $OLDEST_NIGHTLY
    OLDEST_TEST_OUTPUT=$(echo $OLDEST_NIGHTLY | cut -d '-' -f 1-5).test.output.txt
    $DROPBOX delete $OLDEST_TEST_OUTPUT || true
    OLDEST_TEST_FAILED_OUTPUT=$(echo $OLDEST_NIGHTLY | cut -d '-' -f 1-5).test.failed.output.txt
    $DROPBOX delete $OLDEST_TEST_FAILED_OUTPUT || true
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
    $RUST_NIGHTLY_DIR/bin/rustc -V >> $LOGFILE
    $RUST_NIGHTLY_DIR/bin/rustc -V >> $LOGFILE_FAILED
    echo >> $LOGFILE
    echo >> $LOGFILE_FAILED
    RUST_TEST_THREADS=$(nproc) make test -k >>$LOGFILE 2>&1 || true
    cat $LOGFILE | grep "FAILED" >> $LOGFILE_FAILED
    $DROPBOX -p upload $LOGFILE .
    $DROPBOX -p upload $LOGFILE_FAILED .
    rm $LOGFILE $LOGFILE_FAILED
  fi

  # cleanup
  rm -rf $CARGO_NIGHTLY_DIR/*
  rm -rf $DIST_DIR/*
  rm -rf $RUST_NIGHTLY_DIR/*

  end=$(date +"%s")
  diff=$(($end-$starttest))
  echo "Cargo Test Time: $(($diff / 3600)) hours, $((($diff / 60) % 60)) minutes and $(($diff % 60)) seconds elapsed."
  diff=$(($end-$start))
  echo "Cargo Total Time: $(($diff / 3600)) hours, $((($diff / 60) % 60)) minutes and $(($diff % 60)) seconds elapsed."

  exit 0
done

exit 1
