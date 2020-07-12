[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
[![Build Status](https://travis-ci.com/mellanox/ofed-docker.svg?branch=master)](https://travis-ci.com/mellanox/ofed-docker)

- [Containerized Nvidia Mellanox drivers](#containerized-nvidia-mellanox-drivers)
  * [What are driver containers ?](#what-are-driver-containers--)
  * [Containerized Mellanox OFED driver](#containerized-mellanox-ofed-driver)
    + [Containerized Mellanox OFED - Image build](#containerized-mellanox-ofed---image-build)
      - [Build arguments](#build-arguments)
      - [Build - Ubuntu](#build---ubuntu)
      - [Build - Centos](#build---centos)
    + [Containerized Mellanox OFED - Run](#containerized-mellanox-ofed---run)
  * [Containerized Nvidia Peer Memory Client driver](#containerized-nvidia-peer-memory-client-driver)
    + [Containerized Nvidia Peer Memory Client driver - Image build](#containerized-nvidia-peer-memory-client-driver---image-build)
      - [Build arguments](#build-arguments-1)
      - [Build - Ubuntu](#build---ubuntu-1)
      - [Build - Centos](#build---centos-1)
      - [Containerized Nvidia Peer Memory Client driver - Run](#containerized-nvidia-peer-memory-client-driver---run)
  * [Driver container readiness](#driver-container-readiness)

# Containerized Nvidia Mellanox drivers
This repository provides means to build driver containers for various distributions.

__Driver containers offered:__
- Mellanox OFED driver container : Mellanox out of tree networking driver
- NV Peer Memory driver container : Nvidia Peer memory client driver for GPU-Direct

## What are driver containers ?
Driver containers are containers that allow provisioning of a driver on the host.
They provide several benefits over a standard driver installation, for example:
- Ease of deployment
- Fast installation

## Containerized Mellanox OFED driver
This container is intended to be used as an alternative to host installation by simply deploying
the container image on the host the container will:
* Reload Kernel modules provided by Mellanox OFED
* Mount the container's root fs to `/run/mellanox/drivers/`. Should this directory be mapped to the host,
the content of this container will be made available to be shared with host or other containers. A use-case for it
would be compilation of Nvidia Peer Memory client modules.

### Containerized Mellanox OFED - Image build
It is required to build the image on the same OS and kernel as it will be deployed.

The provided Dockerfiles provide several build arguments to provide the flexibility to build
a container image for various driver version and platforms.

#### Build arguments
- `D_OFED_VERSION` : Mellanox OFED version as appears in [Mellanox OFED download page](https://www.mellanox.com/products/infiniband-drivers/linux/mlnx_ofed),
e.g `5.0-2.1.8.0`
- `D_OS` : Operating System version as appears in Mellanox OFED downlload page, e.g `ubuntu20.04`
- `D_ARCH`: CPU architecture as appears in Mellanox OFED download page, e.g `x86_64`
- `D_BASE_IMAGE` : Base image to be used for driver container image build. Default: `ubuntu:20.04` 

#### Build - Ubuntu
```
# docker build -t ofed-driver \
--build-arg D_BASE_IMAGE=ubuntu:20.04 \
--build-arg D_OFED_VERSION=5.0-2.1.8.0 \
--build-arg D_OS=ubuntu20.04 \
--build-arg D_ARCH=x86_64 \
ubuntu/
```

#### Build - Centos
Coming soon...

### Containerized Mellanox OFED - Run
```
# docker run --rm -it \
-v /run/mellanox/drivers:/run/mellanox/drivers \
-v /etc/network:/etc/network \
--net=host --privileged ofed-driver
```

## Containerized Nvidia Peer Memory Client driver
This container is intended to be used as an alternative to host installation by simply deploying
the container image on the host the container will:
* Compile `nv_peer_mem` kernel module
* Reload `nv_peer_mem` kernel module

As Nvidia peer memory client module requires to be compiled against Mellanox OFED and Nvidia drivers currently installed
on the machine, it expects the root fs where Mellanox OFED drivers are installed to be mounted at `/run/mellanox/drivers`
And the root fs where Nvidia drivers are installed to be mounted at `/run/nvidia/drivers`.

This is best suited when both Mellanox NIC and Nvidia GPU drivers are provisioned via driver
containers as they offer to expose their container rootfs. 

### Containerized Nvidia Peer Memory Client driver - Image build

#### Build arguments

- `D_BASE_IMAGE` Base image to be used when building the container image (Default: `ubuntu:20.04`)
- `D_NV_PEER_MEM_BRANCH` Branch/Tag of nv_peer_memory [repositroy](https://github.com/Mellanox/nv_peer_memory) (Default: `master`)

#### Build - Ubuntu
```
# docker build -t nv-peer-mem \
--build-arg D_BASE_IMAGE=ubuntu:20.04 \
--build-arg D_NV_PEER_MEM_BRANCH=1.0-9 \
gpu-direct/ubuntu/
```

#### Build - Centos
Coming soon...

#### Containerized Nvidia Peer Memory Client driver - Run
In the example below, Mellanox driver container rootfs is mounted on the host at `/run/mellanox/drivers`
and [Nvidia driver container](https://github.com/NVIDIA/nvidia-docker/wiki/Driver-containers-(Beta)) rootfs is mounted on the host at `/run/nvidia/driver`

```
# docker run --rm -it \
-v /run/mellanox/drivers:/run/mellanox/drivers \
-v /run/nvidia/driver:/run/nvidia/drivers \
--privileged nv-peer-mem
```

## Driver container readiness

A driver container load kernel modules into the running kernel preceded by a possible compilation
step.

The process is not atomic as:

1. A driver is often composed of multiple modules which are loaded sequentially into the kernel.
2. Compilation (if it takes place) takes time.

To mark the completion of the driver loading phase by the driver container, 
a file is created at the container's root directory: `/.driver-ready`.
Its existence indicates that the driver has been successfully loaded into the running kernel.
This can be used by a container orchestrator to probe for readiness of a driver container. 
