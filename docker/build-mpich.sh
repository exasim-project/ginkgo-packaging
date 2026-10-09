#!/usr/bin/env bash
# Builds and installs MPICH inside the Docker base stage, GPU-aware for the GPU
# backends.
#   build-mpich.sh <install prefix>
# Configured through BACKEND (cpu|cuda|rocm|sycl), MPICH_VERSION and MPICH_SHA256.
#
# Built from source for every backend: Ubuntu's MPICH is configured with PMIx,
# which its own mpiexec (hydra) does not provide, so multi-rank runs start every
# rank as a singleton.
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

gpu_lib=
case "${BACKEND:?}" in
    cpu) ;;
    cuda)
        cuda_path="${CUDA_HOME:-/usr/local/cuda}"
        # MPICH links libcuda (the driver), which only the host provides at run
        # time. Link against the toolkit's stub; libcuda.so.1 is the name libmpi
        # records, so configure's test programs and later links can resolve it
        # with the stub directory on LD_LIBRARY_PATH (see README.md).
        ln -sf libcuda.so "${cuda_path}/lib64/stubs/libcuda.so.1"
        # lib64 itself too: the -L that --with-cuda adds does not reach MPL's
        # link test for libcudart.
        export LDFLAGS="-L${cuda_path}/lib64 -L${cuda_path}/lib64/stubs ${LDFLAGS:-}"
        export LD_LIBRARY_PATH="${cuda_path}/lib64/stubs:${LD_LIBRARY_PATH:-}"
        configure_args+=(--with-cuda="${cuda_path}")
        gpu_lib=libcuda
        ;;
    rocm)
        configure_args+=(--with-hip="${ROCM_PATH:-/opt/rocm}")
        gpu_lib=libamdhip64
        ;;
    sycl)
        # Level Zero, from the system (libze-dev). The yaksa datatype engine
        # needs Intel's offline compiler (ocloc) for its ZE kernels, which the
        # image does not have; dataloop keeps the GPU-aware transfers.
        configure_args+=(--with-ze --with-datatype-engine=dataloop)
        gpu_lib=libze_loader
        ;;
    *)
        echo "unknown backend ${BACKEND}" >&2
        exit 1
        ;;
esac

cd "${work}"
if ! ./configure "${configure_args[@]}"; then
    # The failing check is only explained in the sub-configure logs.
    for log in config.log src/mpl/config.log; do
        [[ -f "${log}" ]] && { echo "=== ${log} ==="; grep -v "^#define" "${log}" | tail -n 200; }
    done
    exit 1
fi
make -j"$(nproc)"
make install
cd /
rm -rf "${work}"

if [[ -n "${gpu_lib}" ]] && ! ldd "${prefix}/lib/libmpi.so" | grep -q "${gpu_lib}"; then
    echo "MPICH was built without ${BACKEND} support (libmpi does not link ${gpu_lib})" >&2
    ldd "${prefix}/lib/libmpi.so" >&2
    exit 1
fi
"${prefix}/bin/mpichversion"
