#!/usr/bin/env bash
# Builds and installs a GPU-aware MPICH inside the Docker base stage.
#   build-mpich.sh <install prefix>
# Configured through BACKEND (cuda|rocm|sycl), MPICH_VERSION and MPICH_SHA256.
#
# MPICH's configure treats the GPU libraries as optional and silently builds
# without GPU support when it cannot find them, so the result is checked below.
set -euxo pipefail

prefix="$1"
version="${MPICH_VERSION:?}"
work="$(mktemp -d)"

curl -fsSL -o "${work}/mpich.tar.gz" \
    "https://www.mpich.org/static/downloads/${version}/mpich-${version}.tar.gz"
echo "${MPICH_SHA256:?}  ${work}/mpich.tar.gz" | sha256sum -c -
tar -xzf "${work}/mpich.tar.gz" -C "${work}" --strip-components=1

configure_args=(
    --prefix="${prefix}"
    --with-device=ch4:ofi
    --enable-shared
    --disable-static
    --disable-fortran
    --enable-fast=O2
)

case "${BACKEND:?}" in
    cuda)
        cuda_path="${CUDA_HOME:-/usr/local/cuda}"
        # MPICH links libcuda (the driver), which only the host provides at run
        # time. Link against the toolkit's stub; libcuda.so.1 is the name libmpi
        # records, so configure's test programs and later links can resolve it
        # with the stub directory on LD_LIBRARY_PATH (see README.md).
        ln -sf libcuda.so "${cuda_path}/lib64/stubs/libcuda.so.1"
        export LDFLAGS="-L${cuda_path}/lib64/stubs ${LDFLAGS:-}"
        export LD_LIBRARY_PATH="${cuda_path}/lib64/stubs:${LD_LIBRARY_PATH:-}"
        configure_args+=(--with-cuda="${cuda_path}")
        gpu_lib=libcuda
        ;;
    rocm)
        configure_args+=(--with-hip="${ROCM_PATH:-/opt/rocm}")
        gpu_lib=libamdhip64
        ;;
    sycl)
        # Level Zero, from the system (libze-dev).
        configure_args+=(--with-ze)
        gpu_lib=libze_loader
        ;;
    *)
        echo "build-mpich.sh is only for GPU backends, got ${BACKEND}" >&2
        exit 1
        ;;
esac

cd "${work}"
./configure "${configure_args[@]}"
make -j"$(nproc)"
make install
cd /
rm -rf "${work}"

if ! ldd "${prefix}/lib/libmpi.so" | grep -q "${gpu_lib}"; then
    echo "MPICH was built without ${BACKEND} support (libmpi does not link ${gpu_lib})" >&2
    ldd "${prefix}/lib/libmpi.so" >&2
    exit 1
fi
"${prefix}/bin/mpichversion"
