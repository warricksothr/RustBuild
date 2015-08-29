# RustBuild
Scripts and patches to auto build Rustc and Cargo on ARM

**Unofficial** build scripts and binaries for nightly Rust/Cargo on 'arm-unknown-linux-gnueabihf'

This repository comtains the required setup/configuration/build scripts and patches for you to setup your own Rust compilation machine. Pre-built 'unofficial' Rust/Cargo binaries are listed below.

# Binary Downloads
## [Unoffical Binaries]

# Usage Instructions
Run # /bin/bash scripts/setup/build_debian_root.sh <name of container> to build a new container from scratch

Then run # /bin/bash scripts/setup/setup_debian_root.sh <name of container> to download the required sources and do the initial setup of the filesystem for the container. This will start the container with systemd-nspawn and do the final configuration in the container, downloading the system tools required. During the process you will need to configure the dropbox_uploader utility. Follow the prompts when they appear.

Now you have a working container with the ability to build Rust/Cargo arm binaries. To kickstart the process, in the app folder you defined during the dropbox_upload setup, create a "snapshots" folder and copy the oldest snapshot from my [snapshots](https://www.dropbox.com/sh/a7kpdcglzsga8yk/AAAjM05nNf8lkbmpuraKZnEXa?dl=0) folder to use to kickstart your build process.

In order to build a recent version of rust, you'll need to first build an up to date snapshot, then compile the rust binary, and finally create cargo.
This can be achieved with the 3 following commands currently

##Nightly
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh

systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh

systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh

This will build the most recent nightly by, first botstrapping my oldest snapshot to build your own newer snapshot, then compiling a new rust from your new snapshot, finally building cargo from your snapshot and rustc. These will all be uploaded to the root directory of the app folder for immediate use.

Alternatively you can use the following to also build beta and stable releases

##Beta
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh beta

systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh beta

systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh beta

##Stable
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh stable

systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh stable

systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh stable

# More Information
I run this on a odroid XU4 running the latest Arch linux with a 32GB eMMC. I have yet to have a memory failure on the eMMC, but it does get heavy usage, so I am considering a ramdrive as the odroid XU4 has 2gb, and Arch + container building barely reach 800mb during peak compilation.

A typical snapshot + rust + cargo build is about 6 hours with tests.

New snapshots do not need to be built often, so the actual build time for
nightlies is closer to 3.5 hours.

 The container with rust/cargo and the tools runs around 6GB

# Todo
- [x] enhance the scripts to support stable/beta in addition to nightly
- [ ] improve the setup scripts to fail if the required tools are not installed
- [ ] look into finding a way to always use the latest stable openssl
- [ ] automate some of the documentation tasks

# License
All scripts/patches in this repository are licensed under the MIT license.

More information can be found in the LICENSE file in this directory

# Acknowledgements
Inspired and built upon the excellent work of Jorge Aparicio's [ruststrap](https://github.com/japaric/ruststrap)

[Unofficial Binaries]: https://www.dropbox.com/sh/ewam0qujfdfaf19/AAB0_fQF7unuuqwDBZ1dF5fla?dl=0
