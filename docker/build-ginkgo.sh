#!/usr/bin/env bash
# Builds and installs Ginkgo inside the Docker build stage.
#   build-ginkgo.sh <source dir> <install prefix>
# Configured through BACKEND (cpu|cuda|rocm|sycl), WITH_MPI (ON|OFF),
# CUDA_ARCHITECTURES, HIP_ARCHITECTURES and BUILD_JOBS.
set -euxo pipefail

src="$1"
prefix="$2"

cmake_args=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="${prefix}"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DBUILD_SHARED_LIBS=ON
    -DGINKGO_BUILD_TESTS=OFF
    -DGINKGO_BUILD_EXAMPLES=OFF
    -DGINKGO_BUILD_BENCHMARKS=OFF
    -DGINKGO_BUILD_DOC=OFF
    -DGINKGO_BUILD_REFERENCE=ON
    -DGINKGO_BUILD_OMP=ON
    -DGINKGO_BUILD_HWLOC=OFF
    -DGINKGO_BUILD_PAPI_SDE=OFF
    -DGINKGO_BUILD_MPI="${WITH_MPI:-ON}"
    -DGINKGO_BUILD_CUDA=OFF
    -DGINKGO_BUILD_HIP=OFF
    -DGINKGO_BUILD_SYCL=OFF
)

case "${BACKEND:-cpu}" in
    cpu) ;;
    cuda)
        cmake_args+=(
            -DGINKGO_BUILD_CUDA=ON
            -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}"
        )
        ;;
    rocm)
        rocm_path="${ROCM_PATH:-/opt/rocm}"
        cmake_args+=(
            -DGINKGO_BUILD_HIP=ON
            -DCMAKE_HIP_COMPILER="${rocm_path}/llvm/bin/clang++"
            -DCMAKE_HIP_ARCHITECTURES="${HIP_ARCHITECTURES}"
            -DCMAKE_PREFIX_PATH="${rocm_path}"
        )
        ;;
    sycl)
        cmake_args+=(
            -DGINKGO_BUILD_SYCL=ON
            -DCMAKE_C_COMPILER=icx
            -DCMAKE_CXX_COMPILER=icpx
        )
        ;;
    *)
        echo "unknown backend ${BACKEND}" >&2
        exit 1
        ;;
esac

if [[ -n "${BUILD_JOBS:-}" ]]; then
    export CMAKE_BUILD_PARALLEL_LEVEL="${BUILD_JOBS}"
fi

cmake -S "${src}" -B /tmp/ginkgo-build "${cmake_args[@]}"
cmake --build /tmp/ginkgo-build
cmake --install /tmp/ginkgo-build
rm -rf /tmp/ginkgo-build
