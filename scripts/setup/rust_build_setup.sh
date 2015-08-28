#!/bin/env bash

# Setup script to prepare a new jessie debian instance for building rust on arm

set -x
set -e

: ${CHROOT_NAME:=RustBuild}

# Allow custom names
if [ ! -z "$1" ]; then
  CHROOT_NAME="$1"
fi

: ${ROOT:=/chroots/$CHROOT_NAME}
: ${HOME:=$ROOT/root}
: ${BUILD:=$ROOT/build}
: ${OPENSSL_DIR:=$BUILD/openssl}
: ${OPENSSL_VER:=OpenSSL_1_0_2d}
: ${OPENSSL_SRC_DIR:=$OPENSSL_DIR/openssl_src}

cd $ROOT
mkdir -p /build/{snapshot,patches}
mkdir -p /build/nightly/{cargo,rust}
mkdir -p /build/openssl/{dist}

# Get the Rust and Cargo projects
cd $BUILD
git clone https://github.com/rust-lang/rust.git
git clone https://github.com/rust-lang/cargo.git

# Get openssl
cd $OPENSSL_DIR
curl "https://github.com/openssl/openssl/archive/${OPENSSL_VER}.tar.gz" -o ${OPENSSL_VER}.tar.gz
tar xzf ${OPENSSL_VER}.tar.gz -C $OPENSSL_SRC_DIR

# Make the distributable directory
cd $HOME
mkdir -p dist

# Get the dropbox_uploader project script
git clone https://github.com/andreadabrizi/Dropbox-Uploader.git
chmod +x Dropbox-Uploader/dropbox_uploader
ln -s Dropbox-Uploader/dropbox_uploader.sh dropbox_uploader.sh

# Get the project scripts and save them in the root
git clone https://github.com/WarrickSothr/RustBuild.git

# Copy the project scripts to the appropriate directories
cp RustBuild/scripts/build/* ${BUILD}
chmod +x ${BUILD}/*.sh
cp RustBuild/scripts/setup/configure_debian.sh /
chmod +x /configure_debian.sh

# Copy the patches
cp RustBuild/patches/* ${BUILD}/patches

# Run the configuration script in in a systemd nspawn
systemd-nspawn -D ${ROOT} "bash /configure_debian.sh"
