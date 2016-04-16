#!/usr/bin/env bash

# Debian configure script
# This is the script that installs the required dependencies and runs the final setups on the system

set -x
set -e

: ${OPENSSL_DIR:=/build/openssl}
: ${OPENSSL_SRC:=$OPENSSL_DIR/openssl_src}
: ${CMAKE_SRC:=/build/cmake}
: ${CMAKE_TAG:=v3.5.2}
: ${LLVM_SRC:=/build/llvm}
: ${LLVM_BUILD:=/build/llvm_build}

if [ $(($(nprocs) / 2)) >= 1 ]; then
    MAKE_JOBS=$(($(nprocs) / 2))
    if [ $(($(nprocs) % 2)) == 1 ] && [ $(nprocs) > 2 ]; then
        MAKE_JOBS=$(($MAKE_JOBS + 1))
    fi
else
    MAKE_JOBS=1
fi

# Determine the fastest host to use for updating
apt-get install --allow-unauthenticated -qq netselect-apt
netselect-apt
NEW_HOST=$(cat sources.list | grep deb | head -n 1 | sed 's/deb http:\/\///' | sed 's/\/debian\/ stable.*//')
rm sources.list

# Replace the old host in the soruces lists with the new ideal host
SOURCE_FILES=/etc/apt/sources.list.d/*.list
echo "Source Files: $SOURCE_FILES"
for f in $SOURCE_FILES
do
  echo "Updating: $f"
  UPDATED=$(cat $f | sed "s/ftp.us.debian.org/$NEW_HOST/")
  echo "$UPDATED" > $f
done

apt-get update
apt-get install --allow-unauthenticated -qq openssl zlib1g-dev git curl python ccache clang gcc g++ file build-essential pkg-config

# Configure the correct alternatives on the system to ensure we're using clang and clang++ 
# where we should instead of gcc and g++
#update-alternatives --install /usr/bin/gcc gcc /usr/bin/clang 50 --slave /usr/bin/g++ g++ /usr/bin/clang++
# Ignore this. We'll let the rust system handle the decision whether to use clang or not. No reason to pretend gcc is clang or g++ os clang++. That's just a bad setup if we can avoid it.

cd ~
# Set the container tag if it wasn't properly inherited
if [ -z $CONTAINER_TAG ]; then
  if [ -f CONTAINER_TAG ]; then
    CONTAINER_TAG=$(cat CONTAINER_TAG)
  fi
fi

# Run the dropbox uploader configuration script
bash dropbox_uploader.sh

# Make sure our tag directory exists
bash dropbox_uploader.sh mkdir ${CONTAINER_TAG}

# Build OpenSSL with the required information for use in building cargo
cd $OPENSSL_SRC
./config -fPIC shared --prefix=$OPENSSL_DIR/dist
make
make install

# Build a newer cmake through the boostrapping process
cd ${CMAKE_SRC}
./bootstrap
make -j$MAKE_JOBS
make install

# Build a new clang to use :D
cd ${LLVM_BUILD}
cmake \ 
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CROSSCOMPILING=True \
    -DLLVM_DEFAULT_TARGET_TRIPLE=arm-unknown-linux-gnueabihf \
    -DLLVM_TARGETS_TO_BUILD=ARM \
    -DLLVM_TARGET_ARCH=ARM \
    -DCMAKE_C_FLAGS="-O2 -march=armv7 -mfloat-abi=hard" \
    -DCMAKE_CXX_FLAGS="-O2 -march=armv7 -mfloat-abi=hard" \
    -G "Unix Makefiles" \
    ${LLVM_SRC}
make -j$MAKE_JOBS
make install

# Print a file with system info
echo "$(uname -a)" > SYSTEM_INFO
echo "$(dpkg -l | grep libc6)" >> SYSTEM_INFO
echo "$(cmake --version | head -n 1)" >> SYSTEM_INFO
echo "$(ldd --version | head -n 1)" >> SYSTEM_INFO
echo "$(ld --version | head -n 1)" >> SYSTEM_INFO
echo "$(gcc --version | head -n 1)" >> SYSTEM_INFO
echo "$(g++ --version | head -n 1)" >> SYSTEM_INFO
echo "$(clang --version | tr '\\n' '|' | head -n 1)" >> SYSTEM_INFO
echo "$(clang++ --version | tr '\\n' '|' | head -n 1)" >> SYSTEM_INFO
echo "$(ccache --version | head -n 1)" >> SYSTEM_INFO
