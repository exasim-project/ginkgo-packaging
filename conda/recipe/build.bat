@echo on
:: Configures, builds and installs Ginkgo into %LIBRARY_PREFIX%. Windows only
:: gets the CPU backend without MPI, see recipe.yaml. OpenMP is left to
:: Ginkgo's autodetection, which depends on the MSVC OpenMP level. Like
:: Ginkgo's own MSVC CI, half and bfloat16 are disabled: with them the
:: ginkgo_core import library exceeds MSVC's limit of 65535 objects (LNK1189).

cmake -S . -B build -G Ninja %CMAKE_ARGS% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DGINKGO_BUILD_TESTS=OFF ^
    -DGINKGO_BUILD_EXAMPLES=OFF ^
    -DGINKGO_BUILD_BENCHMARKS=OFF ^
    -DGINKGO_BUILD_DOC=OFF ^
    -DGINKGO_BUILD_REFERENCE=ON ^
    -DGINKGO_BUILD_MPI=OFF ^
    -DGINKGO_BUILD_HWLOC=OFF ^
    -DGINKGO_BUILD_PAPI_SDE=OFF ^
    -DGINKGO_BUILD_CUDA=OFF ^
    -DGINKGO_BUILD_HIP=OFF ^
    -DGINKGO_BUILD_SYCL=OFF ^
    -DGINKGO_ENABLE_HALF=OFF ^
    -DGINKGO_ENABLE_BFLOAT16=OFF
if errorlevel 1 exit 1

cmake --build build
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1
