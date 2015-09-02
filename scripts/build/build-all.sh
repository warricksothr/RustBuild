#!/usr/bin/env bash

# This is a script to build a snapshot, rust and cargo binary

set -x
set -e

: ${BUILD_SNAPSHOT_SCRIPT:=~/build-snap.sh}
: ${BUILD_RUST_SCRIPT:=~/build-rust.sh}
: ${BUILD_CARGO_SCRIPT:=~/build-cargo.sh}
: ${BASH_SHELL:=/usr/bin/env bash}
#Defaults to the nightly branch
: ${CHANNEL:=nightly}

if [ ! -z $1 ]; then
  CHANNEL=$1
fi

$BASH_SHELL $BUILD_SNAPSHOT_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_RUST_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_CARGO_SCRIPT $CHANNEL
