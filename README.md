# RustBuild
Scripts and patches to auto build Rust and Cargo on ARM

**Unofficial** build scripts and binaries for nightly Rust/Cargo on 'arm-unknown-linux-gnueabihf'

This repository contains the required setup/configuration/build scripts and patches for you to setup your own Rust compilation machine. Pre-built 'unofficial' Rust/Cargo binaries are listed below.

# Binary Downloads
## [Unoffical Binaries](https://www.dropbox.com/sh/ewam0qujfdfaf19/AAB0_fQF7unuuqwDBZ1dF5fla?dl=0)

# Usage Instructions
Run # /bin/bash scripts/setup/build_debian_root.sh <name of container> to build a new container from scratch

Then run # /bin/bash scripts/setup/setup_debian_root.sh <name of container> to download the required sources and do the initial setup of the filesystem for the container. This will start the container with systemd-nspawn and do the final configuration in the container, downloading the system tools required. During the process you will need to configure the dropbox_uploader utility. Follow the prompts when they appear.

Now you have a working container with the ability to build Rust/Cargo arm binaries. To kickstart the process, in the app folder you defined during the dropbox_upload setup, create a "snapshots" folder and copy the oldest snapshot from my [snapshots](https://www.dropbox.com/sh/a7kpdcglzsga8yk/AAAjM05nNf8lkbmpuraKZnEXa?dl=0) folder to yours. This is essential for your first build process. After that you are entirely reliant on your own binaries. (Alternatively you can cross compile a stage-0 rust compiler on a host machine with your desired target and use that instead.)

In order to build a recent version of rust, you'll need to first build an up to date snapshot, then compile the rust binary, and finally create cargo.
This can be achieved with the 3 following commands currently

##Nightly
```bash
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh
```

This will build the most recent nightly by, first botstrapping my oldest snapshot to build your own newer snapshot, then compiling a new rust from your new snapshot, finally building cargo from your snapshot and rustc. These will all be uploaded to the root directory of the app folder for immediate use.

Alternatively you can use the following to also build beta and stable releases

##Beta
```bash
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh beta
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh beta
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh betadd
```

##Stable
```bash
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh stable
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh stable
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh stable
```

**NOTE:** Neither the beta or stable tags support a unique version of cargo as cargo is still sub 1.0. So passing a tag currently doesn't do anything special, but may in the future.

# More Information
I run this on a ODROID XU4 running the latest Arch linux and 3.10 HMP kernel with a 32GB eMMC. I have yet to have a memory failure on the eMMC, but it does get heavy usage, so I am considering a ramdrive as the ODROID XU4 has 2gb, and the Arch system + build container running barely reach 800MB during peak compilation.

A typical snapshot + rust + cargo build is about 6 hours with tests.

New snapshots do not need to be built often, so the actual build time for
nightlies is closer to 3.5 hours.

The container with rust/cargo nightlies, a rust snapshot, the tools, and the in progress compilation runs around 6GB

These scripts are configured to compile the snapshots and full rust compilers with Clang for the improvement in build time over a slight reduction in runtime performance. (This may change as new versions of clang are promoted to debian stable.)

## Builds tested on:
 - ODROID XU4 (8/31/2015)
 - CubieBoard2  (8/30/2015)
 - Samsung Note 10.1 (2014) in Arch chroot (8/31/2015)

# Todo
- [x] enhance the scripts to support stable/beta in addition to nightly
- [x] improve the setup scripts to fail if the required tools are not installed
- [ ] look into finding a way to always use the latest stable openssl
- [ ] automate some of the documentation tasks
- [x] automate the build process in a container on the ODROID XU4
- [ ] look into cross compiling snapshots for other architectures to provide a baseline to allow others to easily build a rustc and cargo implementation for those platforms
- [ ] consider a raspbian root in addition to the jessie one for raspberry pi support
- [ ] rebuild dropbox directory structure to support multiple difference architectures
- [ ] build a caching script around the dropbox upload script to reduce network usage for recently built snapshots (and maybe nightlies)

# License
All scripts/patches in this repository are licensed under the MIT license.

More information can be found in the LICENSE file in this directory

# Acknowledgements
Inspired and built upon the excellent work of Jorge Aparicio's [ruststrap](https://github.com/japaric/ruststrap)
