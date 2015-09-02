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

# Run the dropbox uploader configuration script
cd ~
bash dropbox_uploader.sh

# Make sure our dropbox root directory exists
bash dropbox_uploader.sh mkdir ${CONTAINER_TAG}

# Build OpenSSL with the required information for use in building cargo
cd $OPENSSL_SRC
./config -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install
