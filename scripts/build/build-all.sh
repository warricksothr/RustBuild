#!/usr/bin/env bash

# This is a script to build a snapshot, rust and cargo binary

set -x
set -e

echo "Started from $PWD"
echo "Moving into home directory $HOME"
cd $HOME
echo "Building from $PWD"

: ${BUILD_SNAPSHOT_SCRIPT:=~/build-snap.sh}
: ${BUILD_RUST_SCRIPT:=~/build-rust.sh}
: ${BUILD_CARGO_SCRIPT:=~/build-cargo.sh}
: ${BASH_SHELL:=/usr/bin/env bash}
#Defaults to the nightly branch
: ${CHANNEL:=nightly}
: ${DEBUG:=false}

export DEBUG=$DEBUG
#Make sure we're using the correct tag for this container
if [ -z $CONTAINER_TAG ]; then
  if [ -f "${HOME}/CONTAINER_TAG" ]; then
    export CONTAINER_TAG="$(cat ${HOME}/CONTAINER_TAG)"
  fi
fi

if [ ! -z $1 ]; then
  CHANNEL=$1
fi

start_time="$(date +%s)"
$BASH_SHELL $BUILD_SNAPSHOT_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_RUST_SCRIPT $CHANNEL
$BASH_SHELL $BUILD_CARGO_SCRIPT $CHANNEL
end_time="$(date +%s)"
running_time="$((end_time-start_time))"
# Prints Hours:Minutes:Seconds
printf "Elapsed Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"
