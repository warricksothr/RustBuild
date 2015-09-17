#!/usr/bin/env bash

#
# This script will walk through the containers and update their repositories
# to the latest RustBuild version.
#

set -x
set -e

: ${CHROOT_DIR:=/chroots}

if [ ! -z $1 ]; then
  CHROOT_DIR="$1"
fi

directories=($(ls -d ${CHROOT_DIR}/*))

for file in ${directories[@]}; do
  if [ -d $file ]; then
    container=${file}
    container_root=${container}/root
    rust_build_dir=${container_root}/RustBuild
    if [ -d $rust_build_dir ]; then
      opwd=$PWD
      cd $rust_build_dir
      git reset
      git clean -df
      git checkout -- .
      git pull
      cd $opwd
    fi
  fi
done
