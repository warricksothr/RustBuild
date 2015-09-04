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
  if $already_running; then
    machinectl terminate $1
  fi
}

set -x

CHROOT="/chroots"

# Build process start time
start_time="$(date +%s)"

# Debian target
TARGET="RustBuild"
# Request an already running instance terminate
stop_running_machine "$TARGET"

# Build nightly, beta, and then stable in the same container consecutively
systemd-nspawn -D $CHROOT/$TARGET /bin/bash /root/build-all.sh || stop_running_machine "$TARGET"
systemd-nspawn -D $CHROOT/$TARGET /bin/bash /root/build-all.sh beta || stop_running_machine "$TARGET"
systemd-nspawn -D $CHROOT/$TARGET /bin/bash /root/build-all.sh stable || stop_running_machine "$TARGET"

# Make sure we've exited the container at the end
stop_running_machine "$TARGET"

# Benchmark the build time for all of the debian containers
debian_end_time="$(date +%s)"
debian_running_time="$((debian_end_time-start_time))"
printf "Debian Total Elapsed Build Time: %02d:%02d:%02d\n" "$((debian_running_time/3600%24))" "$((debian_running_time/60%60))" "$((debian_running_time%60))"

# Get a timestamp for the start of the next build
next_start="$(date +%s)"

# Raspbian target
TARGET="RustBuild-raspbian"
# Request an already running instance terminate
stop_running_machine "$TARGET"

# Build nightly, beta, and then stable in the same container consecutively
systemd-nspawn -D $CHROOT/$TARGET /bin/bash /root/build-all.sh || stop_running_machine "$TARGET"
#systemd-nspawn -D $CHROOT/$TARGET /bin/bash /root/build-all.sh beta || stop_running_machine "$TARGET"
#systemd-nspawn -D $CHROOT/$TARGET /bin/bash /root/build-all.sh stable || stop_running_machine "$TARGET"

# Make sure we've exited the container at the end
stop_running_machine "$TARGET"

# Benchmark the build time for all of the debian containers
raspbian_end_time="$(date +%s)"
raspbian_running_time="$((raspbian_end_time-next_start_time))"
printf "Raspbian Total Elapsed Build Time: %02d:%02d:%02d\n" "$((raspbian_running_time/3600%24))" "$((raspbian_running_time/60%60))" "$((raspbian_running_time%60))"

end_time="$(date +%s)"
running_time="$((end_time-start_time))"
# Prints Hours:Minutes:Seconds
printf "Total Elapsed Build Time: %02d:%02d:%02d\n" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"
