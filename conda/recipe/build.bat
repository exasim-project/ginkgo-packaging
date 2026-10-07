@echo on
:: Configures, builds and installs Ginkgo into %LIBRARY_PREFIX%. Windows only
:: gets the CPU backend without MPI, see recipe.yaml. OpenMP is left to
:: Ginkgo's autodetection, which depends on the MSVC OpenMP level.

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
    -DGINKGO_BUILD_SYCL=OFF
if errorlevel 1 exit 1

cmake --build build
if errorlevel 1 exit 1

cmake --install build
if errorlevel 1 exit 1
