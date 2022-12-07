# NOTE: match to the supported MLNX_OFED driver version matrix
ARG D_BASE_VERSION="8.5"
ARG D_BASE_IMAGE="docker.io/library/rockylinux"
FROM "${D_BASE_IMAGE}:${D_BASE_VERSION}"

# Install dependencies
RUN dnf install --assumeyes epel-release rocky-release \
    # Install packages
    && dnf install --assumeyes \
    autoconf automake binutils curl dmidecode ethtool gcc git hostname \
    iproute kmod lbzip2 libmnl libtool lsof make pciutils perl procps \
    python2 python36 python36-devel rpm-build tcl tk wget \
    # Cleanup
    && dnf clean all \
    && rm -rf /var/cache /var/log/dnf* /var/log/yum.*

ARG D_ARCH="x86_64"
ARG D_BASE_OS="rhel"
ARG D_BASE_VERSION
ARG D_OS_BOARD="amd64-usr"
ENV D_OS_BOARD=$D_OS_BOARD
ARG D_OS_CHANNEL="stable"
ENV D_OS_CHANNEL=${D_OS_CHANNEL}
ARG D_OS_VERSION="3227.2.4"
ENV D_OS_VERSION=${D_OS_VERSION}

ARG D_OFED_VERSION="5.7-1.0.2.0"
ARG D_OFED_BASE_URL="https://linux.mellanox.com/public/repo/mlnx_ofed/${D_OFED_VERSION}/${D_BASE_OS}${D_BASE_VERSION}"
ARG D_OFED_PKG_NAMES="mft mlnx-iproute2 mlnx-ofa_kernel mlnx-ofa_kernel-devel mlnx-ofa_kernel-source ofed-scripts"
ARG D_OFED_PKG_EXTENSION="rpm"
ARG D_OFED_REPO_FILE="mellanox_mlnx_ofed.repo"

ARG D_WITH_FLAGS="\
    --enable-container-build \
    --build-dummy-mods \
    --with-core-mod \
    --with-ipoib-mod \
    --with-ipoib-cm \
    --with-ipoib-allmulti \
    --with-ipoib_debug-mod \
    --with-ipoib_debug_data-mod \
    --with-sdp_debug_data-mod \
    --with-user_mad-mod \
    --with-user_access-mod \
    --with-addr_trans-mod \
    --with-mlx5-mod \
    --with-mlx5_core-mod \
    --with-mlx5_inf-mod \
    --with-mlx5_debug-mod \
    --with-mlxfw-mod \
    --with-madeye-mod \
    --with-memtrack \
    --with-debug-info \
    --with-nfsrdma-mod \
    --with-scsi_transport_srp-mod \
    --with-odp \
    --with-wqe-format \
    --with-pa-mr \
    --with-nvmf_host-mod \
    --with-nvmf_target-mod \
    --with-bf-device-emulation \
    --with-mlxdevm-mod \
    --with-bf-power-failure-event \
    --with-gds \
    --with-mlx5-fs-debugfs \
    --with-sf-cfg-drv \
    "
ENV D_WITH_FLAGS=${D_WITH_FLAGS}

# Install packages
WORKDIR /
RUN curl -sL "${D_OFED_BASE_URL}/${D_OFED_REPO_FILE}" > "/etc/yum.repos.d/${D_OFED_REPO_FILE}" \
    && dnf install --assumeyes ${D_OFED_PKG_NAMES} \
    # Cleanup
    && dnf clean all \
    && rm -rf /var/cache /var/log/dnf* /var/log/yum.*

ADD ./entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
