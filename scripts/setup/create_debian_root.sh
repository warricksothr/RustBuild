#!/bin/env bash

# debootstrap, curl, and git need to be installed for this script
# This script needs to be run with root privleges

set -x
set -e

: ${CHROOT_DIR:=/chroots}
: ${DEBIAN_VERSION:=jessie}
: ${CHROOT_NAME:=RustBuild}

# Optional custom name for the chroot
if [ ! -z "$1" ]; then
  CHROOT_NAME=$1
fi

mkdir -p $CHROOT_DIR
cd $CHROOT_DIR
#debootstrap --arch armhf $DEBIAN_VERSION $CHROOT_NAME
