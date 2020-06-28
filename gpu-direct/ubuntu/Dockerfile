ARG D_BASE_IMAGE=ubuntu:20.04
FROM ${D_BASE_IMAGE}

ARG D_NV_PEER_MEM_BRANCH=master

WORKDIR /root
# Install packages
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get -yq install vim git libncurses-dev flex bison openssl libssl-dev dkms \
libelf-dev libudev-dev libpci-dev libiberty-dev autoconf debhelper

# Clone Repo
RUN /bin/bash -c 'git clone --branch ${D_NV_PEER_MEM_BRANCH} https://github.com/Mellanox/nv_peer_memory.git'

# Apply fix for nvidia symver. see issue: https://github.com/Mellanox/nv_peer_memory/issues/70 for more information
# TODO: Remove this fix once its addressed in nv_peer_memory project.
ADD ./patches/nv-symver.fix ./nv_peer_memory
RUN /bin/bash -c 'cd nv_peer_memory && git apply nv-symver.fix'

ADD ./entrypoint.sh ./

ENTRYPOINT ["/root/entrypoint.sh"]
