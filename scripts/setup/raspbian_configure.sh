#!/usr/bin/env bash

# This is the script that installs the required dependencies and runs the final setups on the system

set -x
set -e

: ${OPENSSL_DIR:=/build/openssl}
: ${OPENSSL_SRC:=$OPENSSL_DIR/openssl_src}

cd /
apt-key add raspbian.public.key
rm raspbian.public.key

apt-get update
apt-get install --allow-unauthenticated -qq openssl zlib1g-dev git curl python ccache clang gcc g++ cmake file build-essential pkg-config

cd ~
# Set the container tag if it wasn't properly inherited
if [ -z $CONTAINER_TAG ]; then
  if [ -f CONTAINER_TAG ]; then
    CONTAINER_TAG=$(cat CONTAINER_TAG)
  fi
fi

# Run the dropbox uploader configuration script
bash dropbox_uploader.sh

# Make sure our dropbox root directory exists
bash dropbox_uploader.sh mkdir ${CONTAINER_TAG}

# Try to Download and Upload the first ARMv6 compatible snapshot
curl -L "https://www.dropbox.com/s/ss9gaxvhosko7y7/rust-stage0-2015-04-27-857ef6e-linux-arm-5f6b8f68b46e8229a88476f8a3eda676903f0fbb.tar.bz2\?dl\=0" -o rust-stage0-2015-04-27-857ef6e-linux-arm-5f6b8f68b46e8229a88476f8a3eda676903f0fbb.tar.bz2 || true
if [ -f "rust-stage0-2015-04-27-857ef6e-linux-arm-5f6b8f68b46e8229a88476f8a3eda676903f0fbb.tar.bz2" ]; then
  bash dropbox_uploader.sh mkdir "${CONTAINER_TAG}/snapshots"
  bash dropbox_uploader.sh upload "rust-stage0-2015-04-27-857ef6e-linux-arm-5f6b8f68b46e8229a88476f8a3eda676903f0fbb.tar.bz2" "${CONTAINER_TAG}/snapshots"
  rm "rust-stage0-2015-04-27-857ef6e-linux-arm-5f6b8f68b46e8229a88476f8a3eda676903f0fbb.tar.bz2"
else
  echo "You will need to copy your own snapshot to the ${CONTAINER_TAG}/snapshots directory"
fi

# Build OpenSSL with the required information for use in building cargo
cd $OPENSSL_SRC
./config -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install
