#!/bin/bash -x


VENDOR=0x15b3
DRIVER_PATH=/sys/bus/pci/drivers/mlx5_core

set_driver_readiness() {
    touch /.driver-ready
}

unset_driver_readiness() {
    rm -f /.driver-ready
}

exit_on_error() {
    $@
    if [[ $? -ne 0 ]]; then
        echo "Error occured while executing: $1"
        exit 1
    fi
}

mount_rootfs() {
    echo "Mounting Mellanox OFED driver container rootfs..."
    mount --make-runbindable /sys
    mount --make-private /sys
    mkdir -p /run/mellanox/drivers
    mount --rbind / /run/mellanox/drivers
}

unmount_rootfs() {
    echo "Unmounting Mellanox OFED driver rootfs..."
    if findmnt -r -o TARGET | grep "/run/mellanox/drivers" > /dev/null; then
      umount -l -R /run/mellanox/drivers
    fi
}

handle_signal() {
    unset_driver_readiness
    unmount_rootfs
    delete_udev_rules
    echo "Stopping Mellanox OFED Driver..."
    /etc/init.d/openibd force-stop
    exit 0
}

ofed_exist_for_kernel() {
    # check if mlx5_core exists in dkms under running kernel, this should be sufficient to hint us if
    # OFED drivers are installed for the running kernel
    if [[ -e /usr/lib/modules/${KVER}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko ]]; then
        echo "OFED driver found for kernel"
        return 0
    fi
    echo "No OFED driver found for kernel ${KVER}"
    return 1

}

rebuild_driver() {
    # Rebuild driver in case installed driver kernel version differs from running kernel
    echo "Rebuilding driver"
    #dnf -y clean expire-cache
    #dkms autoinstall
}

start_driver() {
    modprobe -r rpcrdma ib_srpt ib_isert rdma_cm
    modprobe -r i40iw ib_core
    /etc/init.d/openibd restart
    if [[ $? -ne 0 ]]; then
        echo "Error occured while restarting driver"
        return 1
    fi
    ofed_info -s
}

# Install the kernel modules header/builtin/order files and generate the kernel version string.
_install_prerequisites() {
    echo "Enabling RHOCP and EUS RPM repos..."
    eval local $(cat /host/etc/os-release | grep ^VERSION_ID=)
    OPENSHIFT_VERSION=${VERSION_ID:-4.9}
    eval local $(cat /etc/os-release | grep ^VERSION_ID=)
    RHEL_VERSION=${VERSION_ID:-8.4}

    dnf config-manager --set-enabled rhocp-${OPENSHIFT_VERSION}-for-rhel-8-x86_64-rpms || true
    if ! dnf makecache --releasever=${RHEL_VERSION}; then
    	dnf config-manager --set-disabled rhocp-${OPENSHIFT_VERSION}-for-rhel-8-x86_64-rpms
    fi

    dnf config-manager --set-enabled rhel-8-for-x86_64-baseos-eus-rpms  || true
    if ! dnf makecache --releasever=${RHEL_VERSION}; then
    	dnf config-manager --set-disabled rhel-8-for-x86_64-baseos-eus-rpms
    fi

    echo "Installing dependencies"
    dnf -q -y --releasever=${RHEL_VERSION} install createrepo elfutils-libelf-devel kernel-rpm-macros numactl-libs

    echo "Installing Linux kernel headers..."
    dnf -q -y --releasever=${RHEL_VERSION} install kernel-headers-${KVER} kernel-devel-${KVER}

    echo "Installing Linux kernel module files..."
    dnf -q -y --releasever=${RHEL_VERSION} install kernel-core-${KVER}

    # Prevent depmod from giving a WARNING about missing files 
    touch /lib/modules/${KVER}/modules.order
    touch /lib/modules/${KVER}/modules.builtin

    depmod ${KVER}

    echo "Generating Linux kernel version string..."
    sh /usr/src/kernels/${KVER}/scripts/extract-vmlinux /lib/modules/${KVER}/vmlinuz | strings | grep -E '^Linux version' | sed 's/^\(.*\)\s\+(.*)$/\1/' > version
    if [ -z "$(<version)" ]; then
        echo "Could not locate Linux kernel version string" >&2
        return 1
    fi
    mv version /lib/modules/${KVER}/proc
}

_install_ofed() {
    # Install OFED
    # mlnxofedinstall --without-fw-update --kernel-only --force ${D_WITHOUT_FLAGS}
    /bin/bash -c '/root/${D_OFED_PATH}/mlnxofedinstall --without-fw-update --kernel-only --add-kernel-support --distro ${D_OS} --skip-repo --force ${D_WITHOUT_FLAGS}'
    
    # Post Install steps
    
    # dont load kernel (builtin) esp4/6 modules related to innova
    sed -i '/ESP_OFFLOAD_LOAD=yes/c\ESP_OFFLOAD_LOAD=no' /etc/infiniband/openib.conf
    
    # Put a post start hook in place for restoring network configurations of mellanox net devs
    cp /root/${D_OFED_PATH}/docs/scripts/openibd-post-start-configure-interfaces/post-start-hook.sh /etc/infiniband/post-start-hook.sh
    chmod +x /etc/infiniband/post-start-hook.sh
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

KVER=$(uname -r)

# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
ofed_exist_for_kernel
if [[ $? -ne 0 ]]; then
    _install_prerequisites
    _install_ofed
    rebuild_driver
fi

unload_modules rpcrdma rdma_cm
create_udev_rules
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
