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
: ${OPENSSL_DIR:=$BUILD/openssl}
: ${OPENSSL_VER:=OpenSSL_1_0_2d}
: ${OPENSSL_SRC_DIR:=$OPENSSL_DIR/openssl_src}

cd $ROOT
mkdir -p $BUILD
mkdir -p $BUILD/{snapshot,patches}
mkdir -p $BUILD/nightly/{cargo,rust}
mkdir -p $BUILD/openssl/{dist,openssl_src}

# Get the raspbian public key
wget http://archive.raspbian.org/raspbian.public.key

# Get the Rust and Cargo projects
cd $BUILD
git clone --recursive https://github.com/rust-lang/rust.git
mkdir -p rust/build
git clone --recursive https://github.com/rust-lang/cargo.git

# Get openssl
cd $OPENSSL_DIR
curl -L "https://github.com/openssl/openssl/archive/${OPENSSL_VER}.tar.gz" -o ${OPENSSL_VER}.tar.gz
tar xzf ${OPENSSL_VER}.tar.gz
mv $OPENSSL_DIR/openssl-$OPENSSL_VER/* $OPENSSL_SRC_DIR
rm -r $OPENSSL_DIR/openssl-$OPENSSL_VER

# Make the distributable directory
cd $CHROOT_HOME
mkdir -p dist

#We're going to store the container tag in the bash shell configuration
echo "export CONTAINER_TAG=${CHROOT_TAG}" >> .bashrc

# Get the dropbox_uploader project script
git clone https://github.com/andreafabrizi/Dropbox-Uploader.git
chmod +x Dropbox-Uploader/dropbox_uploader.sh
ln -s Dropbox-Uploader/dropbox_uploader.sh dropbox_uploader.sh

# Get the project scripts and save them in the root
git clone https://github.com/WarrickSothr/RustBuild.git

# link the project scripts to the appropriate directories
chmod +x RustBuild/scripts/build/*.sh
ln -s RustBuild/scripts/build/*.sh .
chmod +x RustBuild/scripts/setup/configure_debian.sh
ln -s RustBuild/scripts/setup/configure_debian.sh .

# Copy the patches
cp RustBuild/patches/* ${BUILD}/patches

# Copy the apt preferences and sources
cp RustBuild/etc/apt/preferences.d/*.pref ${ROOT}/etc/apt/preferences.d
cp RustBuild/etc/apt/sources.list.d/*.list ${ROOT}/etc/apt/sources.list.d

# Run the configuration script in in a systemd nspawn
systemd-nspawn -D ${ROOT} /bin/bash ~/raspbian_configure.sh
