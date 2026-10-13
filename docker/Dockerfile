# syntax=docker/dockerfile:1
#
# Ginkgo development images. One Dockerfile serves all backends; the base image
# and backend are chosen with build args (see docker/backends.json and
# .github/workflows/docker.yml):
#
#   docker build -f docker/Dockerfile \
#     --build-arg BASE_IMAGE=nvidia/cuda:12.9.1-devel-ubuntu24.04 \
#     --build-arg BACKEND=cuda --build-arg GINKGO_REF=v1.11.0 .
#
# The resulting image is the base image plus Ginkgo installed to /opt/ginkgo,
# ready to build applications with find_package(Ginkgo).

ARG BASE_IMAGE=ubuntu:24.04

FROM ${BASE_IMAGE} AS base
ARG DEBIAN_FRONTEND=noninteractive
ARG BACKEND=cpu
ARG WITH_MPI=ON
# MPICH rather than Open MPI: its ABI is shared by Cray MPICH, Intel MPI and
# MVAPICH, so on HPC systems the host's (GPU-aware) MPI can replace the one
# in the image at runtime, see README.md. MPICH is built from source: Ubuntu's
# package expects a PMIx launcher, so its own mpiexec starts every rank as a
# singleton. The CUDA and ROCm images build it GPU-aware, because the GPU builds
# of Ginkgo pass device buffers straight to MPI. The SYCL image uses the Intel
# MPI of its oneAPI base image instead (also MPICH ABI, and the MPI FindMPI picks
# there through I_MPI_ROOT); I_MPI_OFFLOAD=1 makes it accept device buffers.
ARG MPICH_VERSION=5.0.2
ARG MPICH_SHA256=928c2f18d350a91443fe8024ad01ce2c6009e9c551e0a73e797fc567f119137d
# The unquoted $( ) adds the optional packages, the word splitting is intended.
# intel-ocloc: Intel's offline GPU compiler, needed to compile SYCL code ahead of
# time (e.g. Kokkos with Kokkos_ARCH_INTEL_PVC, -fsycl-targets=spir64_gen).
# hadolint ignore=SC2046
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake curl file git ninja-build \
        $( [ "${BACKEND}" = "sycl" ] && echo intel-ocloc ) \
    && rm -rf /var/lib/apt/lists/*

COPY docker/build-mpich.sh /usr/local/bin/build-mpich.sh
RUN if [ "${WITH_MPI}" = "ON" ] && [ "${BACKEND}" != "sycl" ]; then \
        BACKEND="${BACKEND}" MPICH_VERSION="${MPICH_VERSION}" \
        MPICH_SHA256="${MPICH_SHA256}" build-mpich.sh /opt/mpich \
        && echo /opt/mpich/lib > /etc/ld.so.conf.d/mpich.conf \
        && ldconfig; \
    fi
# Harmless in the images without /opt/mpich.
ENV PATH=/opt/mpich/bin:${PATH}
# Only read by Intel MPI (SYCL image): pass device buffers through MPI.
ENV I_MPI_OFFLOAD=1


FROM base AS build
ARG BACKEND=cpu
ARG WITH_MPI=ON
ARG GINKGO_REF=develop
ARG GINKGO_REPO=https://github.com/ginkgo-project/ginkgo.git
ARG CUDA_ARCHITECTURES="70-real;80-real;90-real;90-virtual"
# CDNA only, Ginkgo's HIP kernels need 64-wide wavefronts (no RDNA).
ARG HIP_ARCHITECTURES="gfx908;gfx90a;gfx942"
# Kernel instantiation is memory hungry, GPU builds run out of RAM on hosted
# runners with the default parallelism.
ARG BUILD_JOBS=

RUN git clone --filter=blob:none "${GINKGO_REPO}" /src/ginkgo \
    && git -C /src/ginkgo checkout --detach "${GINKGO_REF}" \
    && git -C /src/ginkgo rev-parse HEAD > /src/ginkgo-revision

COPY docker/build-ginkgo.sh /usr/local/bin/build-ginkgo.sh
RUN BACKEND="${BACKEND}" WITH_MPI="${WITH_MPI}" \
    CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
    HIP_ARCHITECTURES="${HIP_ARCHITECTURES}" \
    BUILD_JOBS="${BUILD_JOBS}" \
    build-ginkgo.sh /src/ginkgo /opt/ginkgo \
    && mkdir -p /opt/ginkgo/share \
    && cp /src/ginkgo-revision /opt/ginkgo/share/ginkgo-revision


FROM base AS final
ARG BACKEND=cpu
ARG GINKGO_REF=develop
ARG GINKGO_VERSION=
COPY --from=build /opt/ginkgo /opt/ginkgo
ENV Ginkgo_ROOT=/opt/ginkgo \
    CMAKE_PREFIX_PATH=/opt/ginkgo \
    LD_LIBRARY_PATH=/opt/ginkgo/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
LABEL org.opencontainers.image.title="ginkgo-${BACKEND}" \
      org.opencontainers.image.description="Ginkgo ${GINKGO_VERSION} (${BACKEND}) installed in /opt/ginkgo" \
      org.opencontainers.image.source="https://github.com/ginkgo-project/ginkgo" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.version="${GINKGO_VERSION}" \
      org.ginkgo-project.ref="${GINKGO_REF}" \
      org.ginkgo-project.backend="${BACKEND}"
