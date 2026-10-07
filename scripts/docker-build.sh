#!/usr/bin/env bash
# Builds a Ginkgo image with the local docker, using the same settings as
# docker.yml:  docker-build.sh <backend> <ginkgo ref>
set -euo pipefail

cd "$(dirname "$0")/.."
backend="${1:-cpu}"
ref="${2:-develop}"
config() { jq -r --arg b "${backend}" --arg k "$1" '.[$b][$k]' docker/backends.json; }

if [[ "$(config base_image)" == "null" ]]; then
    echo "unknown backend ${backend}" >&2
    exit 1
fi

docker build -f docker/Dockerfile \
    --build-arg BASE_IMAGE="$(config base_image)" \
    --build-arg BACKEND="${backend}" \
    --build-arg WITH_MPI="$(config with_mpi)" \
    --build-arg BUILD_JOBS="$(config build_jobs)" \
    --build-arg GINKGO_REF="${ref}" \
    --build-arg GINKGO_VERSION="${ref#v}" \
    -t "ginkgo-${backend}:${ref#v}" .
