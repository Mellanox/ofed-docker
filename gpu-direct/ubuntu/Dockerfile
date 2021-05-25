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
ADD ./patches/nv-symver.fix .
RUN cd nv_peer_memory && \
    if [ "$(git rev-list 1.0-9..HEAD | wc -l)" -eq 0 ]; then git apply ../nv-symver.fix; fi

ADD ./entrypoint.sh ./

ENTRYPOINT ["/root/entrypoint.sh"]
