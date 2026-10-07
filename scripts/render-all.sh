#!/usr/bin/env bash
# Renders the conda recipe for every backend, platform and supported Ginkgo
# version without building, which catches recipe and variant errors in
# seconds. Used by check.yml and `pixi run render`.
set -euo pipefail

cd "$(dirname "$0")/.."

# version:ref pairs, develop uses a nightly-style version.
versions=("1.10.0:v1.10.0" "1.11.0:v1.11.0" "2.0.0.dev0:develop")
combos=(
    linux-64:cpu osx-arm64:cpu osx-64:cpu win-64:cpu
    linux-64:cuda linux-64:sycl linux-64:rocm
)

status=0
for v in "${versions[@]}"; do
    for combo in "${combos[@]}"; do
        platform="${combo%%:*}"
        backend="${combo##*:}"
        if ! out=$(GINKGO_VERSION="${v%%:*}" GINKGO_REF="${v##*:}" \
            rattler-build build --render-only \
            --recipe conda/recipe/recipe.yaml \
            --variant-config conda/variants/base.yaml \
            --variant-config "conda/variants/${backend}.yaml" \
            --target-platform "${platform}" \
            --channel conda-forge 2> render.err); then
            echo "FAILED ${v%%:*} ${platform}/${backend}"
            cat render.err
            status=1
            continue
        fi
        builds=$(jq -r '[.[].recipe.build.string] | join(" ")' <<< "${out#"${out%%[*}"}")
        echo "ok ${v%%:*} ${platform}/${backend}: ${builds}"
    done
done
rm -f render.err
exit "${status}"
