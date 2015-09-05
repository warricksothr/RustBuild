#!/usr/bin/env bash

#
# Setup script to prepare a new raspbian instance for building rust on arm
# 
# The Raspberry Pi is an ARMv6 device with support for Hard Float. This
# container is an attempt at creating an environment for constructing 
# ARMv6-armhf compatible binaries for Rust and Cargo.
#

set -x
set -e

: ${CHROOT_NAME:=RustBuild-raspbian}
: ${CHROOT_TAG:=ARMv6-armhf}

# Allow custom names
if [ ! -z "$1" ]; then
  CHROOT_NAME="$1"
fi

# Allow custom tags
if [ ! -z "$2" ]; then
  CHROOT_TAG="$2"
fi

: ${ROOT:=/chroots/$CHROOT_NAME}
: ${CHROOT_HOME:=$ROOT/root}
: ${BUILD:=$ROOT/build}
: ${OPT:=$ROOT/opt}
: ${OPENSSL_DIR:=$BUILD/openssl}
: ${OPENSSL_VER:=OpenSSL_1_0_2d}
: ${OPENSSL_SRC_DIR:=$OPENSSL_DIR/openssl_src}

cd $ROOT
mkdir -p $BUILD
mkdir -p $BUILD/{snapshot,patches}
mkdir -p $BUILD/openssl/{dist,openssl_src}

# Make the opt directories for our cargo and rust builds
mkdir -p $OPT/rust_{nightly,beta,stable}/{cargo,rust}

# Get the raspbian public key
if [ ! -f raspbian.public.key ]; then
  wget http://archive.raspbian.org/raspbian.public.key
fi

# Get the Rust and Cargo projects
cd $BUILD
if [ -d rust ]; then
  cd rust
  git checkout .
  git pull
  cd ..
else
  git clone --recursive https://github.com/rust-lang/rust.git
fi
mkdir -p rust/build
if [ -d cargo ]; then
  cd cargo
  git checkout .
  git pull
  cd ..
else
  git clone --recursive https://github.com/rust-lang/cargo.git
fi

# Get openssl
cd $OPENSSL_DIR
  if [ ! -d $OPENSSL_SRC_DIR ]; then
  curl -L "https://github.com/openssl/openssl/archive/${OPENSSL_VER}.tar.gz" -o ${OPENSSL_VER}.tar.gz
  tar xzf ${OPENSSL_VER}.tar.gz
  mv $OPENSSL_DIR/openssl-$OPENSSL_VER/* $OPENSSL_SRC_DIR
  rm -r $OPENSSL_DIR/openssl-$OPENSSL_VER
fi

# Make the distributable directory
cd $CHROOT_HOME
mkdir -p dist

#We're going to store the container tag in the bash shell configuration
echo "export CONTAINER_TAG=${CHROOT_TAG}" >> .bashrc
# And in a file in the root home directory
echo "${CHROOT_TAG}" > CONTAINER_TAG

# Get the dropbox_uploader project script
if [ -d Dropbox-Uploader ]; then
  cd Dropbox-Uploader
  git checkout .
  git pull
  cd ..
else
  git clone https://github.com/andreafabrizi/Dropbox-Uploader.git
fi
chmod +x Dropbox-Uploader/dropbox_uploader.sh
ln -sf Dropbox-Uploader/dropbox_uploader.sh dropbox_uploader.sh

# Get the project scripts and save them in the root
if [ -d RustBuild ]; then
  cd RustBuild
  git checkout .
  git pull
  cd ..
else
  git clone https://github.com/WarrickSothr/RustBuild.git
fi

# link the project scripts to the appropriate directories
chmod +x RustBuild/scripts/build/*.sh
ln -sf RustBuild/scripts/build/*.sh .
chmod +x RustBuild/scripts/setup/raspbian_configure.sh
ln -sf RustBuild/scripts/setup/raspbian_configure.sh .

# Copy the patches
cp RustBuild/patches/* ${BUILD}/patches

# Run the configuration script in in a systemd nspawn
systemd-nspawn -D ${ROOT} /bin/bash ~/raspbian_configure.sh
