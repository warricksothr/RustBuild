#!/usr/bin/env bash

# Wonderful build script to run nightly
# This is what builds our rust binaries

# Build nightly, beta, and then stable
start_time="$(date +%s)"
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh beta
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh stable
running_time="$(((date +%s)-start_time))"
# Prints Days:Hours:Minutes:Seconds
printf "Total Elapsed Build Time: %02d:%02d:%02d:%02d\n" "$((running_time/86400))" "$((running_time/3600%24))" "$((running_time/60%60))" "$((running_time%60))"
