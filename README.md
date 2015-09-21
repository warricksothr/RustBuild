# RustBuild [![Twitter URL](https://img.shields.io/twitter/url/http/SothrDev.svg?style=social)](https://twitter.com/SothrDev)

Scripts and patches to auto build Rust and Cargo on an ARM machine

**Unofficial** build scripts and binaries for nightly Rust/Cargo on 'arm-unknown-linux-gnueabihf'

This repository contains the required setup/configuration/build scripts and patches for you to setup your own Rust compilation machine. Pre-built 'unofficial' Rust/Cargo binaries are listed below for those who do not want to run their own build machine or are unable to.

# Binary Downloads

For those familiar with Jorge Aparicio's [ruststrap](https://github.com/japaric/ruststrap) project; the ARMv6 builds are incredibly similar to his documented process. They're built in a Raspbian container with glibc 2.13 and GCC 4.8. This means that they're compatible with ARMv6-armhf systems and up (Thanks to the requirement by ARM, that all newer ARM architectures are required to recognize and run old ARM architectures). So anyone with a Raspberry Pi running the Wheezy distribution of Raspbian should use those, even if it's the ARMv7 Raspberry Pi 2. However, if the Raspberry Pi 2 is running the newer Jessie distribution of Raspbian, that should be able to run the ARMv7 binaries as it meets the requirement of glibc >= 2.19.

### [Architecture Releases Directory](https://www.dropbox.com/sh/ewam0qujfdfaf19/AAB0_fQF7unuuqwDBZ1dF5fla?dl=0)
## ARMv7

(Built on Debian Jessie, with Clang 3.5,  GLIBC 2.19-18, OpenSSL 1.2.0d static)

For ARMv7+ Devices with atleast GLIBC 2.19

(Including Raspberry Pi 2 __running Raspbian Jessie__ (8))

### [Unofficial Nightly Binaries (1.5.0)](https://www.dropbox.com/sh/gcat9erkhd4acq1/AABSM3TWIqcrSFx0LRijUNAYa?dl=0)
### [Unofficial Beta Binaries (1.4.0)](https://www.dropbox.com/sh/0ie217m6yiv5wic/AAC3nAwnC5uUPFcbTuz6EmLRa?dl=0)
### [Unofficial Stable Binaries (1.3.0)](https://www.dropbox.com/sh/zth6wky23ih88c8/AABTYCOBeaTDBIASKoWyAPwma?dl=0)

## ARMv6-armhf
(Built on Raspbian with GCC 4.8, GLIBC 2.13-38+rpi2+deb7u8, OpenSSL 1.2.0d static)

For ARMv6+ Devices with atleast GLIBC 2.13

For Raspberry Pi (A, A+, B, B+, 2) running Raspbian Wheezy (7)

### [Unofficial Nightly Binaries (1.5.0)](https://www.dropbox.com/sh/866e4szgdvjmy45/AABP1moHeCTyST9B3qJIdVfva?dl=0)
### [Unofficial Beta Binaries (1.4.0)](https://www.dropbox.com/sh/ausedh4kwrx5rug/AACXoXri73xfQNw3-EsF38Zga?dl=0)
### [Unofficial Stable Binaries (1.3.0)](https://www.dropbox.com/sh/laespfc9u77hga6/AACy-arsOzQe2nT1hvcWegoea?dl=0)

## Builds tested on:
 - ODROID XU4 (@Today This is the build server) [ARMv7](#armv7)[ARMv6-armhf](#armv6-armhf)
 - CubieBoard2 (8/30/2015) [ARMv7](#armv7)
 - Samsung Note 10.1 (2014) in Arch chroot (9/21/2015) [ARMv7](#armv7)
 - Raspberry Pi B (9/6/2015) [ARMv6-armhf](#armv6-armhf)

# Binary Install/Uninstall Instructions

Using the binary builds can be achieved in two ways. Ideally, using multirust to manage your rust binaries, or through manual linking on your system. I'm going to cover using multirust as that is the system I prefer to use. In this guide I will walk you through adding the latest nightly binary build to multirust. This can be adapted for the stable and beta builds simply.

Requirements:
  - [Multirust](https://github.com/brson/multirust)
  - One or more binary builds for your system from above.

1.  Create the directory where rust will be installed and move into it. I use "/opt/rust/nightly"
```shell
# mkdir -p /opt/rust/nightly
# cd /opt/rust/nightly
```

2. Download the latest cargo and rust nightly.
```shell
# wget $LATEST_CARGO_TARBALL
# wget $LATEST_RUST_TARBALL
```

3. Extract the releases into the directory
```shell
# tar xzf $LATEST_CARGO_TARBALL && rm $LATEST_CARGO_TARBALL
# tar xzf $LATEST_RUST_TARBALL && rm $LATEST_RUST_TARBALL
```

4. Link multirust to the current extracted rust and cargo.
```shell
# multirust update unofficial-nightly --link-local
# multirust default unofficial-nightly
```

Now you'll have a version of rust installed in a standard place. Other users could also link against it with only the last two steps.

If you'd prefer to install it only for your user, just use a directory in your home for deployment. Something like "~/opt/rust/nightly" would be fine.

Updating is as simple as entering the deployed directory, removing all the files and folders, and then perform steps 2 and 3 again. (Because we used --link-local multirust doesn't care that we've changed the files.)

# Usage Instructions
Run # /bin/bash scripts/setup/debian_root_build.sh <name of container> to build a new container from scratch (in the default /chroots directory).

Then run # /bin/bash scripts/setup/debian_root_setup.sh <name of container> to download the required sources and do the initial setup of the filesystem for the container. This will start the container with systemd-nspawn and do the final configuration in the container, downloading the system tools required. During the process you will need to configure the dropbox_uploader utility. Follow the prompts when they appear.

Now you have a working container with the ability to build Rust/Cargo arm binaries. To kickstart the process, in the app folder you defined during the dropbox_upload setup, create a "snapshots" folder and copy the oldest snapshot from my [snapshots](https://www.dropbox.com/sh/a7kpdcglzsga8yk/AAAjM05nNf8lkbmpuraKZnEXa?dl=0) folder to yours. This is essential for your first build process. After that you are entirely reliant on your own binaries. (Alternatively you can cross compile a stage-0 rust compiler on a host machine with your desired target and use that instead.)

In order to build a recent version of Rust, you'll need to first build an up to date snapshot, then compile the Rust binary, and finally create Cargo. (Cargo will require a previous version of cargo to compile)
This can be achieved with the 3 following commands currently

##Nightly
```shell
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh
```

This will build the most recent nightly by first bootstrapping an older snapshot to build a newer snapshot, then compiling a new Rust from the new snapshot, finally building Cargo from the rustc and a previous version of Cargo. These will all be uploaded to the root directory of the app folder for immediate use.

Alternatively you can use the following to also build beta and stable releases

##Beta
```shell
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh beta
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh beta
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh beta
```

##Stable
```shell
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-snap.sh stable
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-rust.sh stable
systemd-nspawn /chroots/<name of container> /bin/bash ~/build-cargo.sh stable
```

**NOTE:** The beta/stable tags on the cargo builder do not mean the beta/stable channels of Cargo. Cargo is currently sub 1.0.0 so there is nothing but the nightly branch. However the beta/stable tags mean to build cargo with the latest version of the beta/stable rust compiler and cargo (nightly cargo if no previous cargo exists). This means that the beta/stable version of Cargo should be less prone to issues over the nightly compiled Cargo.

# More Information
I run this on a ODROID XU4 running the latest Arch linux and 3.10 HMP kernel with a 32GB eMMC. I have yet to have a memory failure on the eMMC, but it does get heavy usage, so I am considering a ramdrive as the ODROID XU4 has 2gb, and the Arch system + build container running barely reach 800MB during peak compilation.

A typical snapshot + rust + cargo build is about 8 hours with tests.

New snapshots do not need to be built often, so the actual build time for
nightlies is closer to 3.5 hours.

The container with Rust/Cargo nightlies, a Rust snapshot, tools, file cache and the in progress compilation runs around 8GB

These scripts are configured to compile the snapshots and full Rust compilers with Clang for the improvement in build time over a slight reduction in runtime performance. (This may change as new versions of Clang are promoted to debian stable.)

# Todo
- [x] enhance the scripts to support stable/beta in addition to nightly
- [x] improve the setup scripts to fail if the required tools are not installed
- [ ] look into finding a way to always use the latest stable openssl
- [ ] automate some of the documentation tasks
- [x] automate the build process in a container on the ODROID XU4
- [ ] look into cross compiling snapshots for other architectures to provide a baseline to allow others to easily build a rustc and cargo implementation for those platforms
- [x] start work on raspbian container in addition to the jessie one for raspberry pi support
- [x] finish and test a build system on the raspbian container and find a way to test the resulting binaries for ARMv6-armhf compatibility.
- [x] rebuild dropbox directory structure to support multiple difference architectures
- [x] build a caching script around the dropbox upload script to reduce network usage for recently built snapshots (and maybe nightlies)
- [x] add a maximum cache size parameter to the caching script, so that a limit can be put in place.
- [x] build cargo with the latest stable/beta rust versions in addition to the nightly
- [x] find a way to store version info on the latest stable/beta cargo and rust installed to /opt/rust_{beta,stable} so we can avoid having to re-download and deploy those versions that don't change regularly.
- [ ] work on integrating multirust with the /opt/rust_{stable,beta,nightly} instead of managing our paths directly in the build scripts. Additionally this will allow the build machine to work on more than the latest versions of rust and cargo and act as a build machine for other rust code without needing a complex bootstrapping process.

# License
All scripts/patches in this repository are licensed under the MIT license.

More information can be found in the LICENSE file in this directory

# Acknowledgements
Inspired and built upon the excellent work of Jorge Aparicio's [ruststrap](https://github.com/japaric/ruststrap)
