#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -x

ROOTFS=/rootfs/
SCRIPT_DIR=$(dirname "$0")

source "$SCRIPT_DIR/config"

function bootstrap {
    # Make in-ram new root
    rm -rf "$ROOTFS"
    mkdir -p "$ROOTFS"

    # Packages required for building rootfs
    cp /etc/apt/sources.list /etc/apt/sources.old.list
    echo "" > /etc/apt/sources.list
    echo "deb [trusted=yes] http://archive.debian.org/debian-archive/debian stretch main" >> /etc/apt/sources.list
    echo "deb [trusted=yes] http://archive.debian.org/debian-archive/debian-security stretch/updates main" >> /etc/apt/sources.list
    echo "deb [trusted=yes] http://archive.debian.org/debian-archive/debian stretch-backports main" >> /etc/apt/sources.list
    
    # apt-get install libc6=2.24-11+deb9u4
    # apt-mark hold libc6 
    
    apt-get update
    apt-get install -y --no-install-recommends \
        cdebootstrap curl ca-certificates

    cdebootstrap --flavour="$FLAVOUR" "$SUITE" "$ROOTFS" "$MIRROR"

    echo 'Acquire::Language { "en"; };' >  "$ROOTFS/etc/apt/apt.conf.d/99translations"
    echo 'APT::Install-Recommends "0";' >  "$ROOTFS/etc/apt/apt.conf.d/00apt"
    echo 'APT::Install-Suggests "0";'   >> "$ROOTFS/etc/apt/apt.conf.d/00apt"
    # Disable sync after every package installed
    echo 'force-unsafe-io' > "$ROOTFS/etc/dpkg/dpkg.cfg.d/02apt-speedup"

    # Automatic apt-get clean after apt-get ops
    echo 'DSELECT::Clean "always";' > "$ROOTFS/etc/apt/apt.conf.d/99AutomaticClean"

    # Select default suite
    echo "APT::Default-Release \"$SUITE\";" > "$ROOTFS/etc/apt/apt.conf.d/01defaultrelease"

    # Installing packages
    chroot "$ROOTFS" apt-get update
    local pkgs=($PKG_INCLUDE)
    chroot "$ROOTFS" apt-get install -y --no-install-recommends "${pkgs[@]}"

    # Installing useful Python modules
    chroot "$ROOTFS" /bin/bash -c 'pip install wheel'
    chroot "$ROOTFS" /bin/bash -c 'pip install setuptools'
    chroot "$ROOTFS" /bin/bash -c 'pip install awscli'

    cp -r -t "$ROOTFS" "$SCRIPT_DIR"/rootfs/*

    # /tmp is 755 in the base image. Prevent issues when using non-root users.
    chroot "$ROOTFS" chmod 1777 /tmp

    # Configure locales
    chroot "$ROOTFS" /usr/sbin/locale-gen
    chroot "$ROOTFS" /usr/sbin/locale-gen en_US.UTF-8
    chroot "$ROOTFS" /usr/sbin/dpkg-reconfigure locales

    echo 'deb http://archive.debian.org/debian-archive/debian/ '"${DEBIAN_VERSION}"' main contrib non-free' > "$ROOTFS/etc/apt/sources.list"
    #echo 'deb http://archive.debian.org/debian-archive/debian/ '"${DEBIAN_VERSION}"'-updates main contrib non-free' >> "$ROOTFS/etc/apt/sources.list"
    echo 'deb http://archive.debian.org/debian-archive/debian-security/ '"${DEBIAN_VERSION}"'/updates main contrib non-free' >> "$ROOTFS/etc/apt/sources.list"

    chroot "$ROOTFS" /usr/bin/apt-get update
    chroot "$ROOTFS" /usr/bin/apt-get dist-upgrade --yes
}

function cleanup {
    # cleanup.sh must be called ONBUILD too, DRY
    chroot "$ROOTFS" /bin/sh -c 'test -f /cleanup.sh && sh /cleanup.sh'
}

function output {
    cd "$ROOTFS"
    tar --one-file-system --numeric-owner -cf - ./*
}

function main {
    bootstrap 1>&2
    cleanup 1>&2
    output
}

main
