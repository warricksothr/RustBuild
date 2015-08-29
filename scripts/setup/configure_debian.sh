#!/bin/env bash

# This is the script that installs the required dependencies and runs the final setups on the system

set -x
set -e

: ${OPENSSL_DIR:=/build/openssl}
: ${OPENSSL_SRC:=$OPENSSL_DIR/openssl_src}

# Add place to get clang 3.6 as Jessie only includes clang 3.5
echo "deb http://llvm.org/apt/jessie/ llvm-toolchain-jessie-3.6 main \
deb-src http://llvm.org/apt/jessie/ llvm-toolchain-jessie-3.6 main" >> /etc/apt/sources.list.d/llvm-3.6.list
wget -O - http://llvm.org/apt/llvm-snapshot.gpg.key | apt-key add -
rm -

apt-get update -qq
apt-get install --allow-unauthenticated -qq openssl zlib1g-dev git curl python ccache clang-3.6 lldb-3.6 gcc g++ cmake file build-essential pkg-config

# Run the dropbox uploader configuration script
cd ~
bash dropbox_uploader.sh

# Build OpenSSL with the required information for use in building cargo
cd $OPENSSL_SRC
./config -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install
