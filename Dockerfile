## Stage: Build driver
FROM ubuntu:20.04 AS build

# Build Args - pass with --build-arg flag during build
ARG D_OFED_VERSION="5.0-2.1.8.0"
ARG D_OS="ubuntu20.04"
ARG D_ARCH="x86_64"
ARG D_OFED_PATH="MLNX_OFED_LINUX-${D_OFED_VERSION}-${D_OS}-${D_ARCH}"

# Internal arguments
ARG D_WITHOUT_FLAGS="--without-rshim-dkms --without-iser-dkms --without-isert-dkms --without-srp-dkms --without-kernel-mft-dkms --without-mlnx-rdma-rxe-dkms"

# Copy and extract tarball
ADD ./${D_OFED_PATH} /root/${D_OFED_PATH}
RUN apt-get -yq update; apt-get -yq install perl

# Install OFED
RUN /bin/bash -c '/root/MLNX_OFED_LINUX-${D_OFED_VERSION}-${D_OS}-${D_ARCH}/mlnxofedinstall --without-fw-update --kernel-only --force ${D_WITHOUT_FLAGS}'

# Post Install steps

# dont load kernel (builtin) esp4/6 modules related to innova
RUN sed -i '/ESP_OFFLOAD_LOAD=yes/c\ESP_OFFLOAD_LOAD=no' /etc/infiniband/openib.conf

# Put a post start hook in place for restoring network configurations of mellanox net devs
RUN cp /root/MLNX_OFED_LINUX-${D_OFED_VERSION}-${D_OS}-${D_ARCH}/docs/scripts/openibd-post-start-configure-interfaces/post-start-hook.sh /etc/infiniband/post-start-hook.sh && \
    chmod +x /etc/infiniband/post-start-hook.sh

## Stage: Build container
FROM build

WORKDIR /
ADD ./entrypoint.sh /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]