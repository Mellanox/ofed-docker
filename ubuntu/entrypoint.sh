#!/bin/bash -x


VENDOR=0x15b3
DRIVER_PATH=/sys/bus/pci/drivers/mlx5_core

function set_driver_readiness() {
    touch /.driver-ready
}

function unset_driver_readiness() {
    rm -f /.driver-ready
}

function exit_on_error() {
    $@
    if [[ $? -ne 0 ]]; then
        echo "Error occured while executing: $1"
        exit 1
    fi
}

function mount_rootfs() {
    echo "Mounting Mellanox OFED driver container rootfs..."
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

function handle_signal() {
    unset_driver_readiness
    unmount_rootfs
    delete_udev_rules
    echo "Stopping Mellanox OFED Driver..."
    /etc/init.d/openibd force-stop
    exit 0
}

function ofed_exist_for_kernel() {
    # check if mlx5_core exists in dkms under running kernel, this should be sufficient to hint us if
    # OFED drivers are installed for the running kernel
    local KVER=$(uname -r)
    if [[ -e /lib/modules/${KVER}/updates/dkms/mlx5_core.ko ]]; then
        echo "OFED driver found for kernel"
        return 0
    fi
    echo "No OFED driver found for kernel ${KVER}"
    return 1

}

function rebuild_driver() {
    # Rebuild driver in case installed driver kernel version differs from running kernel
    local KVER=$(uname -r)
    echo "Rebuilding driver"
    apt-get -yq update
    apt-get -yq install linux-headers-${KVER} linux-modules-${KVER}
    dkms autoinstall
}

function fix_src_link() {
    local ARCH=$(uname -m)
    local KVER=$(uname -r)
    local target=$(readlink /usr/src/ofa_kernel/default)
    if [[ -e /usr/src/ofa_kernel/${ARCH}/${KVER} ]] && [[ -L /usr/src/ofa_kernel/default ]] && [[ "${target:0:1}" = / ]]; then
        ln -snf "${ARCH}/${KVER}" /usr/src/ofa_kernel/default
    fi
}

function sync_network_configuration_tools() {
    # As part of openibd restart, mlnx_interface_mgr.sh is running and trying to read
    # /etc/network/interfaces file in case ifup exists and netplan doesn't.
    # In case the host doesn't include ifup but the container do we will fail on reading this file
    # and restarting openibd.
    # The container need to work on both cases where the host includes ifup and when it doesn't.
    # In order to support it we will install both ifup and netplan in the container and on run time
    # we will try to read /etc/network/interfaces (which is mounted from host) and if not exist
    # assume that ifup is missing in the host, in such case we will rename the ifup file in the
    # container so that mlnx_interface_mgr.sh will not find it and won't be trying to read missing
    # /etc/network/interfaces file.
    if [[ -e /etc/network/interfaces ]]; then
        echo "/etc/network/interfaces wasn't found, renaming ifup file (/sbin/ifup -> /sbin/ifup.bk)."
        mv /sbin/ifup /sbin/ifup.bk
        return 0
    fi
}
function start_driver() {
    /etc/init.d/openibd restart
    if [[ $? -ne 0 ]]; then
        echo "Error occured while restarting driver"
        return 1
    fi
    ofed_info -s
}

function unload_modules() {
    local module
    for module in $@; do
        grep -q "^${module} " /proc/modules || continue
        unload_modules $(awk '$1=="'${module}'"{print $4}' /proc/modules | tr , ' ')
        echo "Unloading module ${module}..."
        rmmod ${module}
    done
}

function find_mlx_devs() {
    local ethpath
    for ethpath in /sys/class/net/*; do
        if (grep $VENDOR "$ethpath"/device/vendor >/dev/null 2>&1); then
            echo "$ethpath"
        fi
    done
}

# find all available vfs
# return format <pf_name> <vf_name> <vf_index> <vf_mac> <vf_pci_addr>
function find_mlx_vfs() {
    for mlnx_dev in $(find_mlx_devs); do
        for vf in "$mlnx_dev"/device/virtfn[0-9]*/net/*; do
            [[ -d $vf ]] || continue
            pf_name=$(basename "$mlnx_dev") && [[ -n $pf_name ]] || return 1
            vf_name=$(basename "$vf") && [[ -n $vf_name ]] || return 1
            vf_index=$(sed -E 's|.*/virtfn([0-9]+)/.*|\1|' <<<"$vf") && [[ -n $vf_index ]] || return 1
            vf_mac=$(cat "$vf"/address) && [[ -n $vf_mac ]] || return 1
            vf_pci_addr=$(basename $(readlink "$vf"/device)) && [[ -n $vf_pci_addr ]] || return 1

            echo "$pf_name" "$vf_name" "$vf_index" "$vf_mac" "$vf_pci_addr"
        done
    done
}

function set_administrative_mac_for_vf() {
    local pf_name=$1
    local vf_index=$2
    local vf_mac=$3
    ip link set dev "$pf_name" vf "$vf_index" mac "$vf_mac"
}

function driver_rebind_vf() {
    local vf_pci_addr="$1"
    if ! echo "$vf_pci_addr" >$DRIVER_PATH/unbind; then
        echo "failed to unbind dev $vf_pci_addr"
        return 1
    fi
    if ! echo "$vf_pci_addr" >$DRIVER_PATH/bind; then
        echo "failed to bind dev $vf_pci_addr"
        return 1
    fi
}

function fix_guid_for_vfs() {
    local vf_data
    if ! vf_data="$(find_mlx_vfs)"; then
        echo "Failed to read info about VFs"
        return 1
    fi
    while read -r d; do
        [[ -n "$d" ]] || continue
        local vf_info=($d)
        local pf_name=${vf_info[0]}
        local vf_name=${vf_info[1]}
        local vf_index=${vf_info[2]}
        local vf_mac=${vf_info[3]}
        local vf_pci_addr=${vf_info[4]}
        echo "fix guid for VF: $vf_name"
        if ! set_administrative_mac_for_vf "$pf_name" "$vf_index" "$vf_mac"; then
            echo "failed to set mac for $pf_name VF $vf_index"
            return 1
        fi
        if ! driver_rebind_vf "$vf_pci_addr"; then
            echo "failed to rebind $pf_name VF $vf_index, $vf_pci_addr"
            return 1
        fi
    done <<<"$vf_data"
}

function create_udev_rules() {
        cp /lib/udev/rules.d/82-net-setup-link.rules /host/lib/udev/rules.d/

        # Copy 82-net-setup-link.rules dependencies
        cp /lib/udev/mlnx_bf_udev  /host/lib/udev/
        # Ingnore errors during directory creation
        # We don't delete this directory in delete_udev_rules because it could
        # have some files creted by other software or system administrator
        mkdir -p /host/etc/infiniband
        cp /etc/infiniband/vf-net-link-name.sh /host/etc/infiniband/
}

function delete_udev_rules() {
        rm /host/lib/udev/rules.d/82-net-setup-link.rules

        rm /host/lib/udev/mlnx_bf_udev
        rm /host/etc/infiniband/vf-net-link-name.sh
}

# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
ofed_exist_for_kernel
if [[ $? -ne 0 ]]; then
    rebuild_driver
fi
fix_src_link

unload_modules rpcrdma rdma_cm
create_udev_rules
sync_network_configuration_tools
exit_on_error start_driver
mount_rootfs

# Set administrative mac address for VFs. After mac set, VF
# will be unbinded from the driver and then binded again
# These actions are required to force GUID generation for RDMA device
fix_guid_for_vfs

set_driver_readiness
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "handle_signal" EXIT
sleep infinity & wait
