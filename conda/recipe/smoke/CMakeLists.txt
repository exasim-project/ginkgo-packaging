# Smoke test shared by the conda, pixi and docker builds: compiles a small
# program against an installed Ginkgo and solves a tiny system on the
# reference executor, so it runs without a GPU.
cmake_minimum_required(VERSION 3.16)
project(ginkgo-smoke LANGUAGES CXX)

find_package(Ginkgo REQUIRED)

add_executable(ginkgo-smoke main.cpp)
target_link_libraries(ginkgo-smoke PRIVATE Ginkgo::ginkgo)
target_compile_features(ginkgo-smoke PRIVATE cxx_std_17)
