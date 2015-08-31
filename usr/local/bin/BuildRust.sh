#!/usr/bin/env bash

# Wonderful build script to run nightly
# This is what builds our rust binaries

# Build nightly, beta, and then stable
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh beta
systemd-nspawn -D /chroots/RustBuild /bin/bash /root/build-all.sh stable
