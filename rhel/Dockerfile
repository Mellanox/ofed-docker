FROM registry.access.redhat.com/ubi8:latest

ARG D_OFED_VERSION="5.3-1.0.0.1"
ARG D_OS_VERSION="8.2"
ARG D_OS="rhel${D_OS_VERSION}"
ENV D_OS=${D_OS}
ARG D_ARCH="x86_64"
ARG D_OFED_PATH="MLNX_OFED_LINUX-${D_OFED_VERSION}-${D_OS}-${D_ARCH}"
ENV D_OFED_PATH=${D_OFED_PATH}

ARG D_OFED_TARBALL_NAME="${D_OFED_PATH}.tgz"
ARG D_OFED_BASE_URL="https://www.mellanox.com/downloads/ofed/MLNX_OFED-${D_OFED_VERSION}"
ARG D_OFED_URL_PATH="${D_OFED_BASE_URL}/${D_OFED_TARBALL_NAME}"

ARG D_WITHOUT_FLAGS="--without-rshim-dkms --without-iser-dkms --without-isert-dkms --without-srp-dkms --without-kernel-mft-dkms --without-mlnx-rdma-rxe-dkms"
ENV D_WITHOUT_FLAGS=${D_WITHOUT_FLAGS}

# Download and extract tarball
WORKDIR /root
RUN dnf -y install curl && (curl -sL ${D_OFED_URL_PATH} | tar -xzf -)
RUN dnf -y install autoconf automake binutils ethtool gcc git hostname kmod libmnl libtool lsof make pciutils perl procps python36 python36-devel rpm-build tcl tk wget

WORKDIR /
ADD ./entrypoint.sh /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
