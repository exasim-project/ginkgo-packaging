#!/usr/bin/env bash
# Configures, builds and installs Ginkgo into $PREFIX. GINKGO_BACKEND and
# GINKGO_MPI are set by recipe.yaml from the selected variant.
set -euxo pipefail

cmake_args=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
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
    -DGINKGO_BUILD_CUDA=OFF
    -DGINKGO_BUILD_HIP=OFF
    -DGINKGO_BUILD_SYCL=OFF
    # conda-build fixes up the RPATHs itself.
    -DGINKGO_INSTALL_RPATH_DEPENDENCIES=OFF
)

if [[ "${GINKGO_MPI}" == "nompi" ]]; then
    cmake_args+=(-DGINKGO_BUILD_MPI=OFF)
else
    cmake_args+=(-DGINKGO_BUILD_MPI=ON)
fi

case "${GINKGO_BACKEND}" in
    cpu) ;;
    cuda)
        cmake_args+=(
            -DGINKGO_BUILD_CUDA=ON
            -DCMAKE_CUDA_ARCHITECTURES="${GINKGO_CUDA_ARCHITECTURES}"
            -DCMAKE_CUDA_HOST_COMPILER="${CXX}"
            # conda-forge installs the header-only NVTX3 into the host
            # prefix, not next to nvcc where Ginkgo's FindNVTX looks.
            -DNVTX3_INCLUDE_DIR="${PREFIX}/targets/x86_64-linux/include/nvtx3"
        )
        ;;
    rocm)
        # Experimental: uses the system ROCm, see recipe.yaml.
        rocm_path="${ROCM_PATH:-/opt/rocm}"
        export CXX="${CXX:-g++}" CC="${CC:-gcc}"
        cmake_args+=(
            -DGINKGO_BUILD_HIP=ON
            -DCMAKE_HIP_COMPILER="${rocm_path}/llvm/bin/clang++"
            -DCMAKE_HIP_ARCHITECTURES="${GINKGO_HIP_ARCHITECTURES}"
            -DCMAKE_PREFIX_PATH="${rocm_path};${PREFIX}"
        )
        ;;
    sycl)
        # The whole project has to be compiled with the SYCL compiler.
        # IntelSYCLConfig's feature test does not work inside the conda build
        # environment (conda's CMAKE_FIND_ROOT_PATH hides the compiler's own
        # headers and libraries). Ginkgo only uses it optionally and falls
        # back to plain -fsycl flags without it.
        cmake_args+=(
            -DGINKGO_BUILD_SYCL=ON
            -DCMAKE_CXX_COMPILER=icpx
            -DCMAKE_C_COMPILER=icx
            -DCMAKE_DISABLE_FIND_PACKAGE_IntelSYCL=ON
            # MKL::MKL_SYCL needs TBB, which MKLConfig only finds this way.
            -DTBB_DIR="${PREFIX}/lib/cmake/TBB"
        )
        export TBBROOT="${PREFIX}"
        # Fail early, with the compiler's own message, if the SYCL toolchain
        # cannot build a trivial program in this environment.
        printf '#include <sycl/sycl.hpp>\nint main() { sycl::queue q; return 0; }\n' > sycl-check.cpp
        # shellcheck disable=SC2086 # the flag variables are word lists
        icpx -fsycl ${CXXFLAGS:-} sycl-check.cpp ${LDFLAGS:-} -o sycl-check -v 2>&1 | tail -n 60
        test -x sycl-check
        ;;
    *)
        echo "unknown backend ${GINKGO_BACKEND}" >&2
        exit 1
        ;;
esac

# GPU builds instantiate every kernel for every value type; keep memory use in
# check on the hosted runners.
if [[ "${GINKGO_BACKEND}" != "cpu" ]]; then
    export CMAKE_BUILD_PARALLEL_LEVEL="${GINKGO_BUILD_JOBS:-2}"
fi

# shellcheck disable=SC2086 # CMAKE_ARGS is a word list set by conda-build
if ! cmake -S . -B build ${CMAKE_ARGS:-} "${cmake_args[@]}"; then
    # Surface the try_compile details, which CMake only writes to files.
    tail -n 200 build/CMakeFiles/CMakeConfigureLog.yaml || true
    find build -name Compile.log -exec sh -c 'echo "== $1"; cat "$1"' _ {} \; || true
    exit 1
fi
cmake --build build
cmake --install build
