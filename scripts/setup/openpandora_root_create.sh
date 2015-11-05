#!/usr/bin/env bash

#
# debootstrap, curl, and git need to be installed for this script
# This script needs to be run with root privleges
#
# It expects no argurments, but supports two inputs
# 1: An optional name for the container
# 2: An optional arch other then the default arch of armhf
#
# If you are planning on cross compiling, you'll need binfmt and qemu-static 
# properly configured for the arch you chose for this to work.
# 
# I suggest reading https://wiki.debian.org/QemuUserEmulation and customizing
# it to your host linux distribution. I use ArchLinux as the host for my 
# systems, and it has reasonable support in the AUR to get the configured
# quickly.
#
# For example on my Arch machine, if I want to cross compile an container.
# I install binfmt-support and qemu-user-static from AUR with the following
# command: (I use yaourt for package management)
#
# yaourt -S binfmt-support qemu-user-static
#
# Then I use 'update-binfmts --display' to show the architectures available
#
# Finally for arm i run 'binfmt-update --enable qemu-arm' to enable binfmt
# to expose the static qemu for arm to my system for those binaries. This
# process can be followed for any of the architectures supported under the
# 'binfmt-update --display' command.
#
# Note!: In order for systemd-nspawn (or chroot) to support the new binfmt,
#  we'll need an additional configuration file and a system service restarted.
#
# Copy the etc/binfmt.d/qemu-arm.conf file to your /etc/binfmt.d/
# Then run 'systemctl restart systemd-binfmt' to register the binfmt
# Now, before you can run a container you'll need to copy over the applicable
# qemu-<something>-static to the /bin folder of the new container.
# Then you can run this creation script which will boostrap the container
# creation and prepare everything for you.
#
# NOTE!: Emulation in this manner will be slower than running natively on a
# powerful system of the desired architecture. However, this will be much
# faster than trying to compile on an embedded system.
#

set -x
set -e

# enables pattern lists like +(...|...)
shopt -s extglob

: ${CHROOT_DIR:=/chroots}
: ${DEBIAN_VERSION:=lenny}
: ${CHROOT_NAME:=RustBuild-openpandora}
: ${ARCH_NAME:="--arch=armel"}
# List of supported architectures
: ${SUPPORTED_ARCHITECTURE:="[armel]"}
: ${SUPPORTED_ARCHITECTURE_LIST:="+(armel)"}

# Check that the required software is installed before we procede
command -v curl >/dev/null 2>&1 || { echo >&2 "I require curl but it's not installed.  Aborting."; exit 1; }
command -v git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }
command -v debootstrap >/dev/null 2>&1 || { echo >&2 "I require debootstrap but it's not installed.  Aborting."; exit 1; }

# Optional custom name for the chroot
if [ ! -z "$1" ]; then
  CHROOT_NAME=$1
fi

if [ -d $CHROOT_DIR/$CHROOT_NAME ]; then
  read -p "$CHROOT_NAME already exists. Are you sure you want to continue? [y/N]: " -n 1 -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    exit 1;
  fi
fi

# Allow the user to indicate a specified architecture
# This requires the a custom name be specified
if [ ! -z "$2" ]; then
  ARCH_NAME="--arch=$2"
  case $2 in
    $SUPPORTED_ARCHITECTURE_LIST)
      echo "Set container architecture to: $2"
      ;;
    *)
      echo "$2 is not recognized as a supported architecture: $SUPPORTED_ARCHITECTURE" 
      exit 1
    ;;
  esac
fi

mkdir -p $CHROOT_DIR
cd $CHROOT_DIR
debootstrap $ARCH_NAME $DEBIAN_VERSION $CHROOT_NAME

echo "Run 'openpandora_root_setup.sh $CHROOT_NAME' to configure the CHROOT with the required files and links."
