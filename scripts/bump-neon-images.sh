#!/usr/bin/env bash
# Opens (or updates) a pull request on NeoN that points its LRZ GitLab CI at
# the Ginkgo images of the latest nightly. The images are pinned by digest:
# the GitLab runner caches each image as <name>_<tag>.sif and never pulls a
# name again once it has it, so a moving tag like "nightly" would go stale.
# Backends whose nightly-<date> image is missing are left alone.
# Configured through the environment:
#   GH_TOKEN      token with contents and pull-requests write on NEON_REPO
#   NIGHTLY_DATE  date of the nightly, e.g. 20261101
#   GINKGO_SHA    Ginkgo commit the nightly built (for the PR text)
#   IMAGE_OWNER   owner of the ghcr.io images (default exasim-project)
#   NEON_REPO     default exasim-project/NeoN
#   NEON_BASE     branch to target (default develop)
#   RUN_URL       link to the nightly run (for the PR text, optional)
set -euo pipefail

date="${NIGHTLY_DATE:?}"
sha="${GINKGO_SHA:?}"
owner="${IMAGE_OWNER:-exasim-project}"
owner="${owner,,}"
repo="${NEON_REPO:-exasim-project/NeoN}"
base="${NEON_BASE:-develop}"
branch=ci/ginkgo-nightly-images
ci_file=.gitlab-ci.yml
tag="nightly-${date}"

if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "::warning::No NEON_PR_TOKEN secret, not bumping the NeoN images"
    exit 0
fi

# Digest of a public ghcr.io image, empty if the tag does not exist.
digest() {
    local image="$1" token
    token=$(curl -fsSL "https://ghcr.io/token?scope=repository:${image}:pull" | jq -r .token)
    curl -fsSI \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/${image}/manifests/${tag}" 2> /dev/null \
        | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" {print $2}'
}

work=$(mktemp -d)
gh repo clone "${repo}" "${work}" -- --quiet --depth 1 --branch "${base}"
cd "${work}"

bumped=()
for backend in cuda rocm sycl; do
    image="${owner}/ginkgo-${backend}"
    d=$(digest "${image}")
    if [[ -z "${d}" ]]; then
        echo "::warning::ghcr.io/${image}:${tag} does not exist, leaving ${backend} as is"
        continue
    fi
    sed -i -E "s|^( *image: )ghcr\.io/${image}[:@].*$|\1ghcr.io/${image}@${d} # ${tag}|" "${ci_file}"
    bumped+=("${backend}")
done
sed -i 's|^# Dated tags: the runner caches SIF images by name\.$|# Pinned by digest, bumped by the ginkgo-packaging nightly: the runner caches SIF images by name.|' "${ci_file}"

if git diff --quiet; then
    echo "NeoN already uses the images of ${tag}"
    exit 0
fi
git diff

title="ci(lrz): use the Ginkgo ${tag} images"
body="Points the LRZ GitLab CI at the Ginkgo nightly images of ${date} (${bumped[*]}), built from ginkgo-project/ginkgo@${sha}.

The images are pinned by digest because the GitLab runner caches each image by name and does not pull a name it already has.

Opened by the ginkgo-packaging nightly${RUN_URL:+ (${RUN_URL})}; later nightlies update this PR."

gh auth setup-git
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -q -b "${branch}"
git commit -q -am "${title}"
git push -q --force origin "${branch}"

pr=$(gh pr list --repo "${repo}" --head "${branch}" --state open --json number --jq '.[0].number // empty')
if [[ -n "${pr}" ]]; then
    gh pr edit "${pr}" --repo "${repo}" --title "${title}" --body "${body}"
    echo "Updated ${repo}#${pr}"
else
    gh pr create --repo "${repo}" --base "${base}" --head "${branch}" --title "${title}" --body "${body}"
fi
