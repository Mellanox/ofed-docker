#!/bin/bash -x
MOFED=/run/mellanox/drivers
NVIDIA=/run/nvidia/drivers
KERNEL_VERSION=$(uname -r)
# Install linux headers
apt-get -yq install linux-headers-${KERNEL_VERSION}
# Patch filesystem with components from both Mellanox and Nvidia Drivers
ln -sf ${MOFED}/usr/src/ofa_kernel /usr/src/ofa_kernel
ln -sf ${NVIDIA}/usr/src/nvidia-* /usr/src/.
touch /lib/modules/${KERNEL_VERSION}/modules.order
touch /lib/modules/${KERNEL_VERSION}/modules.builtin
mkdir -p /lib/modules/${KERNEL_VERSION}/updates/dkms
ln -sf ${MOFED}/lib/modules/${KERNEL_VERSION}/updates/dkms/* /lib/modules/${KERNEL_VERSION}/updates/dkms/
ln -sf ${NVIDIA}/lib/modules/${KERNEL_VERSION}/updates/dkms/* /lib/modules/${KERNEL_VERSION}/updates/dkms/
ln -sf ${MOFED}/var/lib/dkms/mlnx-ofed-kernel /var/lib/dkms/mlnx-ofed-kernel
ln -sf ${NVIDIA}/var/lib/dkms/nvidia /var/lib/dkms/nvidia
mkdir -p /etc/infiniband
cp /root/nv_peer_memory/nv_peer_mem.conf /etc/infiniband/
# Build NV PEER MEMORY module
cd /root/nv_peer_memory
make clean && make && make install
./nv_peer_mem restart
./nv_peer_mem status
sleep infinity
