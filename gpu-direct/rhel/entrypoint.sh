#!/bin/bash -x
MOFED=/run/mellanox/drivers
NVIDIA=/run/nvidia/driver
KERNEL_VERSION=$(uname -r)
ln -sf ${MOFED}/usr/src/ofa_kernel /usr/src/ofa_kernel
ln -sf ${NVIDIA}/usr/src/nvidia-* /usr/src/.
mkdir -p /lib/modules/${KERNEL_VERSION}
ln -sf /usr/src/kernels/${KERNEL_VERSION} /lib/modules/${KERNEL_VERSION}/build
touch /lib/modules/${KERNEL_VERSION}/modules.order
touch /lib/modules/${KERNEL_VERSION}/modules.builtin
ln -sf ${NVIDIA}/lib/modules/${KERNEL_VERSION}/kernel /lib/modules/${KERNEL_VERSION}/.
cd /root
dnf -y group install "Development Tools"
dnf -y install kernel-devel-${KERNEL_VERSION} kernel-headers-${KERNEL_VERSION} kmod binutils perl elfutils-libelf-devel
git clone https://github.com/Mellanox/nv_peer_memory.git
cd /root/nv_peer_memory
sed -i 's/updates\/dkms/kernel\/drivers\/video/g' create_nv.symvers.sh
./build_module.sh
rpmbuild --rebuild /tmp/nvidia_peer_memory-*
rpm  -ivh /root/rpmbuild/RPMS/x86_64/nvidia_peer_memory-*.rpm
/etc/init.d/nv_peer_mem restart
sleep infinity