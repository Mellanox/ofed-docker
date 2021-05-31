#!/bin/bash -x

# allow builtin nvidia_peermem module from GPU driver,
# if false, forces to use nv_peer_mem module from the image
ALLOW_MOD_FROM_GPU_DRIVER="${ALLOW_MOD_FROM_GPU_DRIVER:-false}"

MOFED=/run/mellanox/drivers
NVIDIA=/run/nvidia/drivers
KERNEL_VERSION=$(uname -r)

function set_driver_readiness() {
    touch /.driver-ready
}

function unset_driver_readiness() {
    rm -f /.driver-ready
}

function exit_on_error() {
    $@
    if [[ $? -ne 0 ]]; then
        echo "ERROR: command execution failed: $1"
        exit 1
    fi
}

# has_files_matching() $1: dir path, $2: grep pattern
function has_files_matching() {
    local DIR_PATH=$1
    local PATTERN=$2
    ls $DIR_PATH 2> /dev/null | grep -E "${PATTERN}" > /dev/null
    return $?
}

function install_prereq_runtime() {
    # Install linux headers
    apt-get -yq update
    apt-get -yq install linux-headers-${KERNEL_VERSION}
    return $?
}

function inject_mofed_driver() {
    # MLNX_OFED is assumed to be installed via DKMs
    if [[ -e ${MOFED}/usr/src/ofa_kernel ]]; then
        ln -sf ${MOFED}/usr/src/ofa_kernel /usr/src/ofa_kernel
    else
        echo "ERROR: Mellanox NIC driver sources not found."
        return 1
    fi

    has_files_matching ${MOFED}/lib/modules/${KERNEL_VERSION}/updates/dkms mlx5
    if  [[ $? -eq 0 ]]; then
        ln -sf ${MOFED}/lib/modules/${KERNEL_VERSION}/updates/dkms/* /lib/modules/${KERNEL_VERSION}/updates/dkms/
    else
        echo "ERROR: Failed to locate Mellanox NIC drivers in mount: ${MOFED}"
        return 1
    fi
    # ln -sf ${MOFED}/var/lib/dkms/mlnx-ofed-kernel /var/lib/dkms/mlnx-ofed-kernel
}

function inject_nvidia_driver() {
    # NVIDIA driver may be installed either with/out DKMs which affects the module location
    # always inject the modules under dkms as thats where nv_peer_mem is looking for the modules
    # alternative is to modify nv_peer_mem/create_nv_symvers.sh to support both locations
    has_files_matching ${NVIDIA}/usr/src/ nvidia-*
    if  [[ $? -eq 0 ]]; then
        ln -sf ${NVIDIA}/usr/src/nvidia-* /usr/src/.
    else
        echo "ERROR: Nvidia GPU driver sources not found."
        return 1
    fi

    has_files_matching ${NVIDIA}/lib/modules/${KERNEL_VERSION}/updates/dkms nvidia
    if [[ $? -eq 0 ]]; then
        ln -sf ${NVIDIA}/lib/modules/${KERNEL_VERSION}/updates/dkms/* /lib/modules/${KERNEL_VERSION}/updates/dkms/
    else
        has_files_matching ${NVIDIA}/lib/modules/${KERNEL_VERSION}/kernel/drivers/video/ nvidia
        if [[ $? -eq 0 ]]; then
            # Driver installed as non dkms kernel module
            ln -sf ${NVIDIA}/lib/modules/${KERNEL_VERSION}/kernel/drivers/video/nvidia* /lib/modules/${KERNEL_VERSION}/updates/dkms/
        else
            echo "ERROR: Failed to locate Nvidia GPU drivers in mount: ${NVIDIA}"
            return 1
        fi
    fi
    # ln -sf ${NVIDIA}/var/lib/dkms/nvidia /var/lib/dkms/nvidia
}

function use_peermem_from_gpu_driver() {
    if ! $ALLOW_MOD_FROM_GPU_DRIVER; then
        return 1
    fi
    # check if GPU driver include nvidia-peermem module
    has_files_matching /lib/modules/${KERNEL_VERSION}/updates/dkms/ nvidia-peermem.ko
    return $?
}

function load_nvidia_peermem() {
    depmod -a "$KERNEL_VERSION" && \
    modprobe nvidia-peermem
    return $?
}

function unload_nvidia_peermem() {
    modprobe -r nvidia-peermem
    return $?
}

function prepare_build_env() {
    # Patch filesystem with components from both Mellanox and Nvidia Drivers
    touch /lib/modules/${KERNEL_VERSION}/modules.order && \
    touch /lib/modules/${KERNEL_VERSION}/modules.builtin && \
    mkdir -p /lib/modules/${KERNEL_VERSION}/updates/dkms && \
    inject_mofed_driver && \
    inject_nvidia_driver
    return $?
}

function build_modules() {
    # Build NV PEER MEMORY module
    mkdir -p /etc/infiniband && \
    cp /root/nv_peer_memory/nv_peer_mem.conf /etc/infiniband/ && \
    cd /root/nv_peer_memory && \
    make clean && \
    make && \
    make install && \
    ./nv_peer_mem restart && \
    ./nv_peer_mem status
    return $?
}

function handle_signal() {
    echo 'Stopping nv_peer_memory driver'
    unset_driver_readiness
    if use_peermem_from_gpu_driver; then
        unload_nvidia_peermem
        return
    fi
    /root/nv_peer_memory/nv_peer_mem stop
}

# Unset driver readiness in case it was set in a previous run of this container
# and container was killed
unset_driver_readiness
exit_on_error install_prereq_runtime
exit_on_error prepare_build_env
if use_peermem_from_gpu_driver; then
    exit_on_error load_nvidia_peermem
else
    exit_on_error build_modules
fi
set_driver_readiness
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "handle_signal" EXIT
sleep infinity & wait
