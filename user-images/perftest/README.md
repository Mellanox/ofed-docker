# Perftest example container

This folder contains Dockerfiles which are used to create a basic container
with both `rdma-core` and `perftest` packages installed.

`Dockerfile`: basic image based on `ubuntu:18.04` with `rdma-core` and `perftest` packages compiled and
installed from sources

`Dockerfile.with-cuda` : basic image based on `ubuntu:18.04` with cuda libraries, `rdma-core` and `perftest`
packages compiled and installed from sources.
`perftest` is compiled with cuda support to support GPU-Direct. To successfully run this container, it is required
to run on a host with both RDMA supporing NIC and Nvidia GPU with NVIDIA container runtime installed on the host.

## Buid args

`D_RDMA_CORE_TAG`: linux-rdma/rdma-core tag to use

`D_PERFTEST_TAG`: linux-rdma/perftest tag to use
