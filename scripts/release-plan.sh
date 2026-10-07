#!/usr/bin/env bash
# Decides which release artifacts still have to be built, so release.yml never
# rebuilds what is already published. Configured through the environment:
#   VERSIONS          space/comma separated Ginkgo versions, e.g. "1.10.0 1.11.0"
#   BUILD_NUMBER      conda build number to look for (default 0)
#   CONDA_BACKENDS    comma separated conda backends to consider
#   DOCKER_BACKENDS   comma separated Docker backends to consider
#   PREFIX_CHANNEL    prefix.dev channel the releases are published to
#   IMAGE_PREFIX      image name prefix, e.g. ghcr.io/ginkgo-project/ginkgo
#   FORCE             "true" builds everything regardless of what exists
# Writes to $GITHUB_OUTPUT (or stdout):
#   versions  all requested versions, sorted, as a JSON list
#   latest    the highest requested version
#   conda     JSON list of {version, backends} that miss conda packages
#   docker    JSON list of {version, backends} that miss Docker images
set -euo pipefail

: "${VERSIONS:?}"
build_number="${BUILD_NUMBER:-0}"
channel="${PREFIX_CHANNEL:?set the PREFIX_CHANNEL repository variable}"
image_prefix="${IMAGE_PREFIX:-ghcr.io/ginkgo-project/ginkgo}"
force="${FORCE:-false}"
out="${GITHUB_OUTPUT:-/dev/stdout}"

# Number of builds (MPI flavours) per backend and platform, keep in sync with
# conda/variants.
expected_builds() {
    case "$1:$2" in
        cpu:win-64) echo 1 ;;
        cpu:* | cuda:*) echo 2 ;;
        *) echo 1 ;;
    esac
}

split() {
    local word
    for word in ${1//,/ }; do echo "${word}"; done
}

# Platforms a backend is built for, keep in sync with conda.yml.
subdirs_for() {
    case "$1" in
        cpu) echo "linux-64 osx-arm64 osx-64 win-64" ;;
        *) echo "linux-64" ;;
    esac
}

versions=$(split "${VERSIONS}" | sed 's/^v//' | sort -uV)
if [[ -z "${versions}" ]]; then
    echo "::error::no version given" >&2
    exit 1
fi
for v in ${versions}; do
    if ! git ls-remote --exit-code --tags https://github.com/ginkgo-project/ginkgo.git \
        "refs/tags/v${v}" > /dev/null; then
        echo "::error::Ginkgo has no tag v${v}" >&2
        exit 1
    fi
done

# Every ginkgo build in the channel as {subdir, version, build, build_number},
# read from the public repodata; empty for a subdir that has none.
files='[]'
for subdir in linux-64 osx-arm64 osx-64 win-64; do
    repodata=$(curl -fsSL "https://prefix.dev/${channel}/${subdir}/repodata.json" 2> /dev/null || echo '{}')
    files=$(jq -c --arg s "${subdir}" --argjson acc "${files}" \
        '$acc + [((.packages // {}) + (.["packages.conda"] // {}))[]
            | select(.name == "ginkgo")
            | {subdir: $s, version, build, build_number}]' <<< "${repodata}")
done

conda='[]'
docker='[]'
for v in ${versions}; do
    missing=()
    for backend in $(split "${CONDA_BACKENDS:-}"); do
        for subdir in $(subdirs_for "${backend}"); do
            count=$(jq --arg v "${v}" --arg s "${subdir}" --arg b "${backend}_" \
                --argjson n "${build_number}" \
                '[.[] | select(.version == $v and .subdir == $s
                    and .build_number == $n
                    and (.build | startswith($b)))] | length' <<< "${files}")
            if [[ "${force}" == "true" || "${count}" -lt "$(expected_builds "${backend}" "${subdir}")" ]]; then
                echo "conda ${v} ${subdir}/${backend} (build ${build_number}): missing" >&2
                missing+=("${backend}")
                break
            fi
            echo "conda ${v} ${subdir}/${backend} (build ${build_number}): published" >&2
        done
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        conda=$(jq -c --arg v "${v}" --arg b "$(IFS=,; echo "${missing[*]}")" \
            '. + [{version: $v, backends: $b}]' <<< "${conda}")
    fi

    missing=()
    for backend in $(split "${DOCKER_BACKENDS:-}"); do
        image="${image_prefix}-${backend}:${v}"
        if [[ "${force}" != "true" ]] && docker buildx imagetools inspect "${image}" > /dev/null 2>&1; then
            echo "docker ${image}: published" >&2
        else
            echo "docker ${image}: missing" >&2
            missing+=("${backend}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        docker=$(jq -c --arg v "${v}" --arg b "$(IFS=,; echo "${missing[*]}")" \
            '. + [{version: $v, backends: $b}]' <<< "${docker}")
    fi
done

{
    echo "versions=$(jq -cR . <<< "${versions}" | jq -cs .)"
    echo "latest=$(tail -n1 <<< "${versions}")"
    echo "conda=${conda}"
    echo "docker=${docker}"
} >> "${out}"
