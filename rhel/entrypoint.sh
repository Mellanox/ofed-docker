#!/bin/bash -x

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
    echo "Stopping Mellanox OFED Driver..."
    /etc/init.d/openibd force-stop
    exit 0
}

ofed_exist_for_kernel() {
    # check if mlx5_core exists in dkms under running kernel, this should be sufficient to hint us if
    # OFED drivers are installed for the running kernel
    if [[ -e /usr/lib/modules/${KERNEL_VERSION}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko ]]; then
        echo "OFED driver found for kernel"
        return 0
    fi
    echo "No OFED driver found for kernel ${KERNEL_VERSION}"
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
    OPENSHIFT_VERSION=4.6
    RHEL_VERSION=8.2

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
    dnf -q -y --releasever=${RHEL_VERSION} install kernel-headers-${KERNEL_VERSION} kernel-devel-${KERNEL_VERSION}

    echo "Installing Linux kernel module files..."
    dnf -q -y --releasever=${RHEL_VERSION} install kernel-core-${KERNEL_VERSION}

    # Prevent depmod from giving a WARNING about missing files 
    touch /lib/modules/${KERNEL_VERSION}/modules.order
    touch /lib/modules/${KERNEL_VERSION}/modules.builtin

    depmod ${KERNEL_VERSION}

    echo "Generating Linux kernel version string..."
    sh /usr/src/kernels/${KERNEL_VERSION}/scripts/extract-vmlinux /lib/modules/${KERNEL_VERSION}/vmlinuz | strings | grep -E '^Linux version' | sed 's/^\(.*\)\s\+(.*)$/\1/' > version
    if [ -z "$(<version)" ]; then
        echo "Could not locate Linux kernel version string" >&2
        return 1
    fi
    mv version /lib/modules/${KERNEL_VERSION}/proc
}

_install_ofed() {
    # Install OFED
    /bin/bash -c '/root/${D_OFED_PATH}/mlnxofedinstall --without-fw-update --kernel-only --add-kernel-support --distro ${D_OS} --skip-repo --force ${D_WITHOUT_FLAGS}'
    
    # Post Install steps
    
    # dont load kernel (builtin) esp4/6 modules related to innova
    sed -i '/ESP_OFFLOAD_LOAD=yes/c\ESP_OFFLOAD_LOAD=no' /etc/infiniband/openib.conf
    
    # Put a post start hook in place for restoring network configurations of mellanox net devs
    cp /root/${D_OFED_PATH}/docs/scripts/openibd-post-start-configure-interfaces/post-start-hook.sh /etc/infiniband/post-start-hook.sh
    chmod +x /etc/infiniband/post-start-hook.sh
}

KERNEL_VERSION=$(uname -r)


# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
ofed_exist_for_kernel
if [[ $? -ne 0 ]]; then
    _install_prerequisites
    _install_ofed
    rebuild_driver
fi

exit_on_error start_driver
mount_rootfs
set_driver_readiness
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "handle_signal" EXIT
sleep infinity & wait
