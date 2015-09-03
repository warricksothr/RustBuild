#!/usr/bin/env bash

# Wonderful build script to run nightly
# This is what builds our rust binaries

# Check the systemd machinectl to see if a machine is running
is_machine_running () {
  local machine_registered="$(machinectl list | grep -F $1 | sed 's/^\s*$1\s.*$/$1/')"
  if [ -z machine_registered ]; then
    return true
  else
    return false
  fi 
}

# Stop a machine if it is already running
stop_running_machine () {
  local already_running=is_machine_running $1
  if already_running; then
    machinectl terminate $1
  fi
}

set -x

# Build process start time
start_time="$(date +%s)"

# Request an already running instance terminate
stop_running_machine "RustBuild"

# Build nightly, beta, and then stable in the same container consecutively
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh || stop_running_machine "RustBuild"
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh beta || stop_running_machine "RustBuild"
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh stable || stop_running_machine "RustBuild"

# Make sure we've exited the container at the end
stop_running_machine "RustBuild"

end_time="$(date +%s)"
running_time="$((end_time-start_time))"
# Prints Hours:Minutes:Seconds
printf "Total Elapsed Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"
