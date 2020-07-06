#!/bin/bash -x

function exit_on_error() {
    $@
    if [[ $? -ne 0 ]]; then
        echo "Error occured while executing: $1"
        exit 1
    fi
}

function mount_rootfs() {
    echo "Mounting OFED driver container rootfs..."
    mount --make-runbindable /sys
    mount --make-private /sys
    mkdir -p /run/mellanox/drivers
    mount --rbind / /run/mellanox/drivers
}

function unmount_rootfs() {
    echo "Unmounting Mellanox OFED driver rootfs..."
    if findmnt -r -o TARGET | grep "/run/mellanox/drivers" > /dev/null; then
      umount -l -R /run/mellanox/drivers
    fi
}

function rebuild_driver() {
    # Rebuild driver in case installed driver kernel version differs from running kernel
    echo "Rebuilding driver"
    apt-get -yq update
    apt-get -yq install linux-headers-$(uname -r)
    dkms autoinstall
}

function start_driver() {
    /etc/init.d/openibd restart
    if [[ $? -ne 0 ]]; then
        echo "Error occured while restarting driver"
        rebuild_driver
        /etc/init.d/openibd restart
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi
    ofed_info -s
}

exit_on_error start_driver
mount_rootfs
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "unmount_rootfs" EXIT
sleep infinity
