#!/bin/bash -x
mount_rootfs() {
    echo "Mounting {{.SpecialResource.Name}} driver rootfs..."
    mount --make-runbindable /sys
    mount --make-private /sys
    mkdir -p /run/mofed/driver
    mount --rbind / /run/mellanox/drivers
}

unmount_rootfs() {
    echo "Unmounting Mellanox OFED driver rootfs..."
    if findmnt -r -o TARGET | grep "/run/mellanox/drivers" > /dev/null; then
      umount -l -R /run/mellanox/drivers
    fi
}

/etc/init.d/openibd restart
ibv_devinfo
mount_rootfs
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "unmount_rootfs" EXIT
sleep infinity
