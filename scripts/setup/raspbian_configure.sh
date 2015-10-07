#!/usr/bin/env bash

# This is the script that installs the required dependencies and runs the final setups on the system

set -x
set -e

: ${OPENSSL_DIR:=/build/openssl}
: ${OPENSSL_SRC:=$OPENSSL_DIR/openssl_src}
: ${CMAKE_SRC:=/build/cmake}
: ${CMAKE_TAG:=v3.3.2}
: ${LLVM_SRC:=/build/llvm}
: ${LLVM_BUILD:=/build/llvm_build}

# Set the sources correctly
echo "deb http://mirrordirector.raspbian.org/raspbian/ wheezy main contrib non-free rpi" > /etc/apt/sources.list
echo "deb http://httpredir.debian.org/debian wheezy-backports main" >> /etc/apt/sources.list
echo "deb http://archive.raspberrypi.org/debian/ wheezy main" >> /etc/apt/sources.list

cd /
apt-key add raspbian.public.key
rm raspbian.public.key

apt-key add raspberrypi.gpg.key
rm raspberrypi.gpg.key

apt-key add archive-key-7.0.asc
rm archive-key-7.0.asc

apt-get update
# GCC-4.8 and G++-4.8
apt-get install --allow-unauthenticated -qq openssl zlib1g-dev git curl python ccache gcc-4.8 g++-4.8 file build-essential pkg-config subversion
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 50 --slave /usr/bin/g++ g++ /usr/bin/g++-4.8
# Later cmake from wheezy-backports to hopefully build Cargo with
apt-get install --allow-unauthenticated -qq -t wheezy-backports cmake

cd ~
# Set the container tag if it wasn't properly inherited
if [ -z $CONTAINER_TAG ]; then
  if [ -f CONTAINER_TAG ]; then
    CONTAINER_TAG=$(cat CONTAINER_TAG)
  fi
fi

# Print a file with system info
echo "$(uname -a)" > SYSTEM_INFO
echo "$(dpkg -l | grep libc6)" >> SYSTEM_INFO
echo "$(ldd --version | head -n 1)" >> SYSTEM_INFO
echo "$(ld --version | head -n 1)" >> SYSTEM_INFO
echo "$(gcc --version | head -n 1)" >> SYSTEM_INFO
echo "$(g++ --version | head -n 1)" >> SYSTEM_INFO
echo "$(clang --version | tr '\\n' '|' | head -n 1)" >> SYSTEM_INFO
echo "$(clang++ --version | tr '\\n' '|' | head -n 1)" >> SYSTEM_INFO
echo "$(ccache --version | head -n 1)" >> SYSTEM_INFO

# Echo settings to the Build Configuration file
echo "USE_CLANG=false" > BUILD_CONFIGURATION

# Run the dropbox uploader configuration script
bash dropbox_uploader.sh

# Make sure our dropbox root directory exists
bash dropbox_uploader.sh mkdir ${CONTAINER_TAG}

# Build OpenSSL with the required information for use in building cargo
cd $OPENSSL_SRC
# configure for armv4 minimum, with an arch of armv6, fPIC so it can be included
# as a static library, produce shared libraries and install it into the openssl/dist directory
./Configure linux-armv4 -march=armv6 -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install

# Build a newer cmake through the boostrapping process
cd ${CMAKE_SRC}
git checkout tags/v3.3.2
./bootstrap
make
make install

# Build a new clang to use :D
cd ${LLVM_BUILD}
cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_TARGETS_TO_BUILD="ARM" \
    -DLLVM_DEFAULT_TARGET_TRIPLE=arm-linux-gnueabihf \
    -DLLVM_TARGET_ARCH="ARM" \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=arm \
    -DCMAKE_C_FLAGS="-O2 -march=armv6 -mfloat-abi=hard -mfpu=vfp" \
    -DCMAKE_CXX_FLAGS="-O2 -march=armv6 -mfloat-abi=hard -mfpu=vfp" \
    -G "Unix Makefiles" \
    ${LLVM_SRC}
make
make install
