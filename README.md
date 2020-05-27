[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
[![Build Status](https://travis-ci.com/adrianchiris/ofed-docker.svg?branch=master)](https://travis-ci.com/adrianchiris/ofed-docker)
# Containerized Mellanox OFED driver

This repository offers Dockerfiles for variours distribution to be used for building a Mellanox OFED driver container.

This container is intended to be used as an alternative to host installation by simply deploying
the container image on the host it will:
* Reload Kernel modules provided by Mellanox OFED
* Mount the container's root fs to `/run/mellanox/drivers/`. Should this directory be mapped to the host,
the content of this container will be made available to be shared with host or other containers. A use-case for it
would be compilation of Peer Memory client modules.


## Containerized Mellanox OFED - Image build

It is required to build the image on the same OS and kernel as it will be deployed.

The provided Dockerfiles provide several build arguments to provide the flexibility to build
a container image for various driver version and platforms.

### Build arguments

- `D_OFED_VERSION` : Mellanox OFED version as appears in [Mellanox OFED download page](https://www.mellanox.com/products/infiniband-drivers/linux/mlnx_ofed),
e.g `5.0-2.1.8.0`
- `D_OS` : Operating System version as appears in Mellanox OFED downlload page, e.g `ubuntu20.04`
- `D_ARCH`: CPU architecture as appears in Mellanox OFED download page, e.g `x86_64` 

### Containerized Mellanox OFED - Ubuntu

```
# docker build -t ofed-driver\
--build-arg D_OFED_VERSION=5.0-2.1.8.0 \
--build-arg D_OS=ubuntu20.04 \
--build-arg D_ARCH=x86_64 \
ubuntu/
```

## Containerized Mellanox OFED - Centos

Coming soon...

## Containerized GPU Direct - Image build

WIP Coming soon...
