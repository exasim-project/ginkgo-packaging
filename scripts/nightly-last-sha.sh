#!/usr/bin/env bash
# Prints the Ginkgo commit that the most recent nightly built, or nothing if
# no nightly has built yet. nightly.yml records that commit as a
# "nightly-build" notice annotation on its plan job; runs that skipped carry
# no such annotation and are passed over.
# Needs GH_TOKEN (actions: read, checks: read) and GITHUB_REPOSITORY.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?}"
current_run="${GITHUB_RUN_ID:-0}"

runs=$(gh api "repos/${repo}/actions/workflows/nightly.yml/runs?per_page=30" \
    --jq ".workflow_runs[] | select(.id != ${current_run} and .status == \"completed\"
        and .conclusion != \"cancelled\") | .id")

for run in ${runs}; do
    job=$(gh api "repos/${repo}/actions/runs/${run}/jobs" \
        --jq '.jobs[] | select(.name == "plan") | .id' | head -n 1)
    [[ -n "${job}" ]] || continue
    sha=$(gh api "repos/${repo}/check-runs/${job}/annotations" \
        --jq '.[] | select(.title == "nightly-build") | .message' | head -n 1)
    if [[ -z "${sha}" ]]; then
        # Nightlies from before the annotation was introduced only left the
        # commit in their log, and printed it even when they skipped.
        log=$(gh api "repos/${repo}/actions/jobs/${job}/logs" 2> /dev/null || true)
        # Match the rendered notice, not the script text the log also echoes.
        if ! grep -qE '##\[notice\].*skipping the nightly' <<< "${log}"; then
            sha=$(grep -oE 'Building ginkgo-project/ginkgo@[0-9a-f]{40}' <<< "${log}" \
                | head -n 1 | cut -d@ -f2 || true)
        fi
    fi
    if [[ -n "${sha}" ]]; then
        echo "${sha}"
        exit 0
    fi
done
