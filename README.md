# ginkgo-packaging

Packaging workflows for [Ginkgo](https://github.com/ginkgo-project/ginkgo):
conda packages (also consumable with pixi) and Docker images, for the CPU,
CUDA, ROCm and SYCL backends. Covers the releases 1.10.0 and 1.11.0, any later
release, and nightly builds of `develop`.

## What gets published

| | cpu | cuda | rocm | sycl |
|---|---|---|---|---|
| conda `linux-64` | nompi, openmpi | nompi, openmpi | experimental, nightly only | nompi |
| conda `osx-arm64`, `osx-64` | nompi, openmpi | – | – | – |
| conda `win-64` | nompi | – | – | – |
| Docker `linux/amd64` | `ginkgo-cpu` | `ginkgo-cuda` | `ginkgo-rocm` | `ginkgo-sycl` |

Toolchains: CUDA 12.9 (the newest that Ginkgo 1.10 supports), ROCm 6.4.4,
oneAPI 2025.2; GCC 14 / Clang 19 / VS 2022 for the conda builds.

**conda** (prefix.dev). Releases go to the channel in the `PREFIX_CHANNEL`
repository variable. Nightlies go to `PREFIX_NIGHTLY_CHANNEL`, with versions
like `2.0.0.dev20261007`. Nightlies need their own channel because those
versions sort above the latest release. The build string picks the variant:
`<backend>_<mpi>_h<hash>_<n>`. A plain install resolves to the CPU build
without MPI, because every other variant is down-prioritized.

```sh
pixi add ginkgo                                       # with https://prefix.dev/<channel> in channels
conda install -c https://prefix.dev/<channel> -c conda-forge "ginkgo=1.11.0=cuda_nompi_*"
conda install -c https://prefix.dev/<nightly channel> -c conda-forge "ginkgo=*=sycl_*"
```

**pixi**: `pixi/example/pixi.toml` shows one environment per variant and
builds the smoke test against it (`pixi run -e cuda smoke`).

**Docker** (`ghcr.io/<owner>/ginkgo-<backend>`). Tags are `1.10.0`,
`1.11.0`, `latest`, `nightly` and `nightly-YYYYMMDD`. Each image is the
backend's devel base image (ubuntu, nvidia/cuda, rocm/dev, intel/oneapi) with
Ginkgo installed in `/opt/ginkgo`, and `CMAKE_PREFIX_PATH` set so
`find_package(Ginkgo)` works out of the box.

## Layout

```
conda/recipe/recipe.yaml     rattler-build recipe, builds any Ginkgo ref
conda/recipe/build.sh|.bat   CMake configuration per backend
conda/recipe/smoke/          small find_package(Ginkgo) + CG solve, used by
                             the conda tests, the pixi example and the Docker job
conda/variants/              base.yaml (toolchain pins) + one file per backend
docker/Dockerfile            one Dockerfile for all backends (build args)
docker/backends.json         base image and settings per backend
pixi.toml                    maintainer tasks: render, build, docker
pixi/example/                consumer example, tested by pixi.yml
scripts/                     render-all, release-plan, install-rocm, docker-build
```

## Workflows

| workflow | trigger | does |
|---|---|---|
| `release.yml` | manual (`versions`, default `1.10.0 1.11.0`), `repository_dispatch: ginkgo-release` | builds and publishes **only what is missing** for the given releases, then tests with pixi |
| `nightly.yml` | daily 02:17 UTC, manual | builds `develop` (skipped if unchanged for a day) into the nightly channel, tags `nightly*` |
| `conda.yml` | reusable, manual | rattler-build per platform and backend, uploads with `rattler-build upload prefix` |
| `docker.yml` | reusable, manual | builds one image per backend, runs the smoke test in it, pushes to ghcr.io |
| `pixi.yml` | reusable, manual | installs the published packages through the pixi example, runs the smoke test |
| `check.yml` | push, PR | actionlint, shellcheck, hadolint, renders all 21 version/platform/backend combinations; real CPU builds when a PR touches `conda/` or `docker/` |

### Releases are built only once

`release.yml` starts with `scripts/release-plan.sh`. For every requested
version and backend, it:

- reads the release channel's repodata on prefix.dev and treats the conda
  build as done only when every platform has all its MPI variants with the
  requested version **and build number**
- checks whether `ghcr.io/<owner>/ginkgo-<backend>:<version>` exists

Only the missing `(version, backend)` pairs go into the build matrix, so
rerunning the workflow after a partial failure fills in the gaps. To rebuild
on purpose, either bump `build_number` (conda) or set `force`.

Nightly uploads replace files from the same day (`--force`). Release uploads
use `--skip-existing` and never overwrite.

### Publishing a new Ginkgo release

Either run *release* by hand with `versions: 1.12.0`, or let the Ginkgo
repository trigger it on release:

```sh
gh api repos/<owner>/ginkgo-packaging/dispatches \
  -f event_type=ginkgo-release -F 'client_payload[version]=1.12.0'
```

## Setup

- Set the repository variables `PREFIX_CHANNEL` (releases) and
  `PREFIX_NIGHTLY_CHANNEL` (nightlies). Both channels must exist on prefix.dev.
- Create the environment `prefix`. Uploads authenticate either way:
  - **trusted publishing** (recommended, no secret): on prefix.dev, add this
    repository as a trusted publisher to both channels. The OIDC token comes
    from the calling workflow, so allow `release.yml` and `nightly.yml`.
  - **API key**: store it as the `PREFIX_API_KEY` secret in the `prefix`
    environment.
- Images are pushed with `GITHUB_TOKEN`; make the ghcr.io packages public
  after the first push.

## Local use

```sh
pixi run render                          # check the recipe for all variants
pixi run build cpu 1.11.0                # conda package into ./output
pixi run build cuda 2.0.0.dev0 develop
pixi run docker rocm v1.11.0             # needs a local docker
```

## Caveats

- **ROCm conda** is experimental. conda-forge ships the HIP compiler but not
  hipBLAS, hipSPARSE, hipRAND or rocThrust. The package is therefore built
  against a system ROCm 6.4.4 (`scripts/install-rocm.sh`) and needs the same
  ROCm in `/opt/rocm` at runtime. It is built only for nightlies, and its job
  may fail without failing the run. Use the `ginkgo-rocm` Docker image for
  anything serious.
- GPU architectures are fixed at build time: CUDA `70;80;90` SASS + `90`
  PTX, HIP `gfx908;gfx90a;gfx942;gfx1030;gfx1100`. Change them in
  `conda/variants/*.yaml` and `docker/Dockerfile`.
- The GPU builds compile with only 2 parallel jobs to stay within hosted
  runner memory. Expect several hours per job; the timeout is 6 h.
