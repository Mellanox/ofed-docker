## Stage: Build driver
ARG D_BASE_IMAGE=ubuntu:20.04
FROM $D_BASE_IMAGE AS build

# Build Args - pass with --build-arg flag during build
ARG D_OFED_VERSION="5.0-2.1.8.0"
ARG D_OS="ubuntu20.04"
ARG D_ARCH="x86_64"
ARG D_OFED_PATH="MLNX_OFED_LINUX-${D_OFED_VERSION}-${D_OS}-${D_ARCH}"

ARG D_OFED_TARBALL_NAME="${D_OFED_PATH}.tgz"
ARG D_OFED_BASE_URL="https://www.mellanox.com/downloads/ofed/MLNX_OFED-${D_OFED_VERSION}"
ARG D_OFED_URL_PATH="${D_OFED_BASE_URL}/${D_OFED_TARBALL_NAME}"

# Internal arguments
ARG D_WITHOUT_FLAGS="--without-rshim-dkms --without-iser-dkms --without-isert-dkms --without-srp-dkms --without-kernel-mft-dkms --without-mlnx-rdma-rxe-dkms"

# Download and extract tarball
WORKDIR /root
RUN set -x && \
    apt-get -yq update && \
    apt-get -yq install curl perl && \
    (curl -sL ${D_OFED_URL_PATH} | tar -xzf -) && \
    /root/${D_OFED_PATH}/mlnxofedinstall --without-fw-update --kernel-only --force ${D_WITHOUT_FLAGS} && \
    rm -rf /tmp/MLNX_OFED_LINUX* && \
    sed -i '/ESP_OFFLOAD_LOAD=yes/c\ESP_OFFLOAD_LOAD=no' /etc/infiniband/openib.conf && \
    cp /root/${D_OFED_PATH}/docs/scripts/openibd-post-start-configure-interfaces/post-start-hook.sh /etc/infiniband/post-start-hook.sh && \
    chmod +x /etc/infiniband/post-start-hook.sh && \
    apt-get -yq install iproute2 net-tools ifupdown linux-modules-$(uname -r) && \
    rm -rf /root/${D_OFED_PATH} && \
    apt-get clean autoclean && \
    rm -rf /var/lib/apt/lists/*

## Stage: Build container
FROM build

WORKDIR /
ADD ./entrypoint.sh /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
