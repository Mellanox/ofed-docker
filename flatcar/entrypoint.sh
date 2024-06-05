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
    if findmnt -r -o TARGET | grep "/run/mellanox/drivers" >/dev/null; then
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
    if [[ -e /usr/lib/modules/${KVER}/extra/mlnx-ofa_kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko.xz ]]; then
        echo "OFED driver found for kernel"
        return 0
    fi
    echo "No OFED driver found for kernel ${KVER}"
    return 1

}

start_driver() {
    unload_modules rpcrdma rdma_cm mlx5_ib ib_uverbs ib_core
    /etc/init.d/openibd restart
    if [[ $? -ne 0 ]]; then
        echo "Error occured while restarting driver"
        return 1
    fi
    ofed_info -s
}

# The developement environment is required to access gcc and binutils
# binutils is particularly required even if we have precompiled kernel interfaces
# as the ld version needs to match the version used to build the linked kernel interfaces later
# Note that container images can only contain precompiled (but not linked) kernel modules
_install_development_env() {
    echo "Installing the Flatcar development environment on the filesystem..."

    # Get the flatcar development environment for a given kernel version.
    # The environment is mounted on a loop device and then we chroot into
    # the mount to build the kernel driver interface.
    # The resulting module files and module dependencies are then archived.
    local dev_image="/tmp/flatcar_developer_container.bin"
    local dev_image_url="https://${D_OS_CHANNEL}.release.flatcar-linux.net/${D_OS_BOARD}/${D_OS_VERSION}/${dev_image##*/}.bz2"

    curl -sL "${dev_image_url}" | lbzip2 -dq >"${dev_image}"
    local sector_size
    sector_size=$(fdisk -l "${dev_image}" | grep "^Sector size" | awk '{ print $4 }')
    local sector_start
    sector_start=$(fdisk -l "${dev_image}" | grep "^${dev_image}*" | awk '{ print $2 }')
    local offset_limit=$((sector_start * sector_size))

    mkdir -p /mnt/flatcar /mnt/dev
    _exec mount -o offset=${offset_limit} ${dev_image} /mnt/dev
    tar -cp -C /mnt/dev . | tar -xpf - -C /mnt/flatcar
    _exec umount -l /mnt/dev
    rm -f "${dev_image}"

    # Version.txt contains some pre-defined environment variables
    # that we will use when building the kernel modules
    curl -fOSsL "https://${D_OS_CHANNEL}.release.flatcar-linux.net/${D_OS_BOARD}/${D_OS_VERSION}/version.txt"
    cp version.txt /usr/src

    # Prepare the mount point for the chroot
    cp --dereference /etc/resolv.conf /mnt/flatcar/etc/
    _exec mount --types proc /proc /mnt/flatcar/proc
    _exec mount --rbind /sys /mnt/flatcar/sys
    _exec mount --make-rslave /mnt/flatcar/sys
    _exec mount --rbind /dev /mnt/flatcar/dev
    _exec mount --make-rslave /mnt/flatcar/dev

    mkdir -p /etc/infiniband /mnt/flatcar/etc/infiniband
    _exec mount --rbind /etc/infiniband /mnt/flatcar/etc/infiniband
    mkdir -p /mnt/flatcar/usr/src
    _exec mount --rbind /usr/src /mnt/flatcar/usr/src

    # Archive the binutils since we need the linker for re-linking the modules
    local OUTPUT_BINUTILS_DIR=/opt/driver/binutils
    if [ ! -e ${OUTPUT_BINUTILS_DIR} ]; then
        mkdir -p ${OUTPUT_BINUTILS_DIR}/libs
        mkdir -p ${OUTPUT_BINUTILS_DIR}/bin
    fi
    local binutils_ver=$(ls -d /mnt/flatcar/usr/lib64/binutils/$(arch)-cros-linux-gnu/*)
    binutils_ver=${binutils_ver##*/}
    cp -r /mnt/flatcar/usr/$(arch)-cros-linux-gnu/binutils-bin/${binutils_ver}/* ${OUTPUT_BINUTILS_DIR}/bin/
    cp -r /mnt/flatcar/usr/lib64/binutils/$(arch)-cros-linux-gnu/${binutils_ver}/* ${OUTPUT_BINUTILS_DIR}/libs/
    cp -a /mnt/flatcar/usr/lib64/*.so* ${OUTPUT_BINUTILS_DIR}/libs/
}

_cleanup_development_env() {
    echo "Cleaning up the development environment..."
    _exec umount -lR /mnt/flatcar/{proc,sys,dev}
    _exec umount -lR /mnt/flatcar/{etc/infiniband,usr/src}
    rm -rf /mnt/flatcar
}

# Install and load the kernel modules header/builtin/order files and generate the kernel version string.
_install_ofed() {
    rm -rf "/usr/lib/modules/${KVER}"
    rm -rf /usr/src/linux*

    # Edit openib settings
    sed -i 's/\(ESP_OFFLOAD_LOAD=\)yes/\1no/' /etc/infiniband/openib.conf
    sed -i 's/\(FORCE_MODE=\)no/\1yes/' /etc/infiniband/openib.conf
    sed -i 's/\(RUN_MLNX_TUNE=\)no/\1yes/' /etc/infiniband/openib.conf

    _install_development_env
    echo "Installing the Flatcar kernel sources into the development environment..."

    # pass the environment variables
    rm -f /mnt/flatcar/etc/build-args
    echo "export D_WITH_FLAGS='${D_WITH_FLAGS}'" | cat >>/mnt/flatcar/etc/build-args

    cat <<'EOF' | chroot /mnt/flatcar /bin/bash
KERNEL_VERSION=$(ls /lib/modules)
KERNEL_STRING=$(echo "${KERNEL_VERSION}" | cut -d "-" -f1)

echo "Installing kernel sources for kernel version ${KERNEL_VERSION}..."
source /etc/os-release
[ $(echo ${VERSION_ID//./ } | awk '{print $1}') -lt 2346 ] && \
    echo "Fixing path for flatcar kernel sources..." && \
    sed -i -e "s;http://builds.developer.core-os.net/boards/;https://storage.googleapis.com/flatcar-jenkins/boards/;g" /etc/portage/make.conf
export $(cat /usr/src/version.txt | xargs)

echo "Installing dependencies..."
rm -rf /var/lib/portage/gentoo
emerge-gitclone && emerge --verbose \
    "coreos-sources::coreos" \
    "linux-sources::coreos" \
    "perl::portage-stable"

echo "Preparing linux headers ${KERNEL_VERSION}..."
pushd /usr/src/linux && make olddefconfig && popd
mkdir -p /usr/src/linux/proc
cp /proc/version /usr/src/linux/proc/

echo "Compiling kernel modules with $(gcc --version | head -1)..."
cp /lib/modules/${KERNEL_VERSION}/build/scripts/module.lds /usr/src/mlnx-ofa_kernel-*/
cd /usr/src/mlnx-ofa_kernel-*/
export IGNORE_CC_MISMATCH=1
export IGNORE_MISSING_MODULE_SYMVERS=1
export CC=$(arch)-cros-linux-gnu-gcc
source /etc/build-args

# dont load kernel (builtin) esp4/6 modules related to innova
cp /etc/infiniband/openib.conf ofed_scripts/openib.conf.tmp

./configure --with-linux=/usr/src/linux --with-linux-obj=/lib/modules/${KERNEL_VERSION}/build/ ${D_WITH_FLAGS}
make && make install
EOF
    mkdir -p /lib/modules/${KVER}
    cp -r /mnt/flatcar/lib/modules/${KVER}/* /lib/modules/${KVER}/
    cp -r /mnt/flatcar/lib/udev/* /lib/udev/
    depmod "${KVER}"

    _cleanup_development_env
}

# Execute binaries by root owning them first
_exec() {
    exec_bin_path=$(command -v "$1")
    exec_user=$(stat -c "%u" "${exec_bin_path}")
    exec_group=$(stat -c "%g" "${exec_bin_path}")
    if [[ "${exec_user}" != "0" || "${exec_group}" != "0" ]]; then
        chown 0:0 "${exec_bin_path}"
        "$@"
        chown "${exec_user}":"${exec_group}" "${exec_bin_path}"
    else
        "$@"
    fi
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

KVER=$(uname -r)

# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
ofed_exist_for_kernel
if [[ $? -ne 0 ]]; then
    _install_ofed
fi

exit_on_error start_driver
mount_rootfs

# Set administrative mac address for VFs. After mac set, VF
# will be unbinded from the driver and then binded again
# These actions are required to force GUID generation for RDMA device
fix_guid_for_vfs

set_driver_readiness
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "handle_signal" EXIT
sleep infinity &
wait
