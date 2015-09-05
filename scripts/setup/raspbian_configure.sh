#!/usr/bin/env bash

# This is the script that installs the required dependencies and runs the final setups on the system

set -x
set -e

: ${OPENSSL_DIR:=/build/openssl}
: ${OPENSSL_SRC:=$OPENSSL_DIR/openssl_src}

# Set the sources correctly
echo "deb http://mirrordirector.raspbian.org/raspbian/ wheezy main contrib non-free rpi" > /etc/apt/sources.list
echo "deb http://httpredir.debian.org/debian wheezy-backports main" >> /etc/apt/sources.list

cd /
apt-key add raspbian.public.key
rm raspbian.public.key

apt-key add raspberrypi.gpg.key
rm add raspberrypi.gpg.key

apt-key add archive-key-7.0.asc
rm archive-key-7.0.asc

apt-get update
# GCC-4.8 and G++-4.8
apt-get install --allow-unauthenticated -qq openssl zlib1g-dev git curl python ccache gcc-4.8 g++-4.8 file build-essential pkg-config
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 50 --slave /usr/bin/g++ g++ /usr/bin/g++-4.8
# Later cmake from wheezy-backports to hopefully build Cargo with
isudo apt-get install --allow-unauthenticated -t wheezy-backports cmake

cd ~
# Set the container tag if it wasn't properly inherited
if [ -z $CONTAINER_TAG ]; then
  if [ -f CONTAINER_TAG ]; then
    CONTAINER_TAG=$(cat CONTAINER_TAG)
  fi
fi

# Print a file with system info
echo "$(uname -a)" > SYSTEM_INFO
echo "$(ldd --version | head -n 1)" >> SYSTEM_INFO
echo "$(ld --version | head -n 1)" >> SYSTEM_INFO
echo "$(gcc --version | head -n 1)" >> SYSTEM_INFO
echo "$(g++ --version | head -n 1)" >> SYSTEM_INFO
echo "$(clang --version | tr '\\n' '|' | head -n 1)" >> SYSTEM_INFO
echo "$(clang++ --version | tr '\\n' '|' | head -n 1)" >> SYSTEM_INFO
echo "$(ccache --version | head -n 1)" >> SYSTEM_INFO

# Run the dropbox uploader configuration script
bash dropbox_uploader.sh

# Make sure our dropbox root directory exists
bash dropbox_uploader.sh mkdir ${CONTAINER_TAG}

# Build OpenSSL with the required information for use in building cargo
cd $OPENSSL_SRC
./config -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install
