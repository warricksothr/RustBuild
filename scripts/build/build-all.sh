#!/usr/bin/env bash

# This is a script to build a snapshot, rust and cargo binary

set -x
set -e

: ${BUILD_SNAPSHOT_SCRIPT:=build_snap.sh}
: ${BUILD_RUST_SCRIPT:=build_rust.sh}
: ${BUILD_CARGO_SCRIPT:=build_cargo.sh}
: ${BASH_SHELL:=/bin/env bash}
#Defaults to the nightly branch
: ${CHANNEL:=nightly}

if [ ! -z $1 ]; then
  CHANNEL=$1
fi

$BASH_SHELL $BUILD_SNAPSHOT_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_RUST_SCRIPT $CHANNEL
#Only need to build cargo with the nightlies as they have no beta/stable branch yet
case $CHANNEL in
  nightly)
    $BASH_SHELL $BUILD_CARGO_SCRIPT
    ;;
  *);;
esac

