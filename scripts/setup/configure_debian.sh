#!/bin/env bash

# This is the script that installs the required dependencies and runs the final setups on the system

set -x
set -e

: ${OPENSSL_DIR:=/build/openssl}
: ${OPENSSL_SRC:=$OPENSSL_DIR/openssl_src}

apt-get update -qq
apt-get install --allow-unauthenticated -qq build-essential openssl git curl clang gcc g++ cmake file pkg-config python ccache

# Run the dropbox uploader configuration script
cd ~
bash dropbox_uploader.sh

# Build OpenSSL with the required information
cd $OPENSSL_SRC
./config -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install
