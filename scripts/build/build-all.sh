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

start_time="$(date +%s)"
$BASH_SHELL $BUILD_SNAPSHOT_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_RUST_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_CARGO_SCRIPT $CHANNEL
running_time="$(((date +%s%N)-start_time))"
# Prints Days:Hours:Minutes:Seconds
printf "Elapsed Build Time: %02d:%02d:%02d:%02d\n" "$((running_time/86400))" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"
