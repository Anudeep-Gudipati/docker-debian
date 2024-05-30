#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -x

ROOTFS=/rootfs
SCRIPT_DIR=$(dirname "$0")

source "$SCRIPT_DIR/config"

function bootstrap {
    # Make in-ram new root
    rm -rf "$ROOTFS"
    mkdir -p "$ROOTFS"
    mount -t tmpfs -o size="$TMPFS_SIZE" none "$ROOTFS"

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

    apt-get download \
        dumb-init \
        busybox \
        libc6 \
        ca-certificates \
        libgcc1

    for pkg in *.deb; do
        dpkg-deb --fsys-tarfile "$pkg" | tar -xf - -C "$ROOTFS";
    done

    chroot "$ROOTFS/" /bin/busybox --install /bin

    # Collecting certificates from ca-certificates package to one file
    find "$ROOTFS/usr/share/ca-certificates" -name '*.crt' -print0 \
        | xargs -0 cat > "$ROOTFS/etc/ssl/certs/ca-certificates.crt"

    cp -r -t "$ROOTFS" "$SCRIPT_DIR"/rootfs/*
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
