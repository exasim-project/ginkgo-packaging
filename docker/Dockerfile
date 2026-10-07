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
ARG WITH_MPI=ON
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake git ninja-build \
        $( [ "${WITH_MPI}" = "ON" ] && echo libopenmpi-dev openmpi-bin ) \
    && rm -rf /var/lib/apt/lists/*


FROM base AS build
ARG BACKEND=cpu
ARG WITH_MPI=ON
ARG GINKGO_REF=develop
ARG GINKGO_REPO=https://github.com/ginkgo-project/ginkgo.git
ARG CUDA_ARCHITECTURES="70-real;80-real;90-real;90-virtual"
ARG HIP_ARCHITECTURES="gfx908;gfx90a;gfx942;gfx1030;gfx1100"
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
