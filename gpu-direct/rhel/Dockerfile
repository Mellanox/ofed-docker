FROM registry.access.redhat.com/ubi8:latest

# Install packages
RUN dnf install -y autoconf git ncurses-devel openssl openssl-devel rpm-build systemd-devel

WORKDIR /root
# Clone Repo
ARG D_NV_PEER_MEM_BRANCH=master
RUN git clone --branch ${D_NV_PEER_MEM_BRANCH} https://github.com/Mellanox/nv_peer_memory.git

# Apply fix for nvidia symver. see issue: https://github.com/Mellanox/nv_peer_memory/issues/70 for more information
ADD ./patches/nv-symver.fix .
RUN cd nv_peer_memory && \
    if [ "$(git rev-list 1.0-9..HEAD | wc -l)" -eq 0 ]; then git apply ../nv-symver.fix; fi

ADD ./entrypoint.sh ./

ENTRYPOINT ["/root/entrypoint.sh"]
