#!/usr/bin/env bash
# Deletes old Ginkgo nightlies from the prefix.dev channel they share with the
# releases. Only files whose version ends in .dev<digits> are considered, so
# releases can never be removed; the newest KEEP nightly versions stay.
# Configured through the environment:
#   PREFIX_CHANNEL   prefix.dev channel
#   PREFIX_API_KEY   API key with delete rights (not needed for DRY_RUN)
#   KEEP             number of nightly versions to keep (default 14)
#   DRY_RUN          "true" only lists what would be deleted
set -euo pipefail

channel="${PREFIX_CHANNEL:?set the PREFIX_CHANNEL repository variable}"
keep="${KEEP:-14}"
dry_run="${DRY_RUN:-false}"
server="${PREFIX_SERVER_URL:-https://prefix.dev}"

if [[ "${dry_run}" != "true" && -z "${PREFIX_API_KEY:-}" ]]; then
    echo "::error::deleting needs the PREFIX_API_KEY secret" >&2
    exit 1
fi

# Every nightly ginkgo file in the channel as "<version> <subdir>/<filename>".
files=""
for subdir in linux-64 osx-arm64 osx-64 win-64 noarch; do
    repodata=$(curl -fsSL "${server}/${channel}/${subdir}/repodata.json" 2> /dev/null || echo '{}')
    files+=$(jq -r --arg s "${subdir}" '
        [(.packages // {}), (.["packages.conda"] // {})]
        | map(to_entries[]) | .[]
        | select(.value.name == "ginkgo" and (.value.version | test("\\.dev[0-9]+$")))
        | "\(.value.version) \($s)/\(.key)"' <<< "${repodata}")
    files+=$'\n'
done
files=$(grep -v '^$' <<< "${files}" || true)

versions=$(cut -d' ' -f1 <<< "${files}" | grep -v '^$' | sort -uV || true)
total=$(grep -c . <<< "${versions}" || true)
echo "${total} nightly versions in ${channel}, keeping the newest ${keep}"
if [[ "${total}" -le "${keep}" ]]; then
    exit 0
fi

status=0
for version in $(head -n $((total - keep)) <<< "${versions}"); do
    while read -r path; do
        if [[ "${dry_run}" == "true" ]]; then
            echo "would delete ${path}"
            continue
        fi
        code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
            -H "Authorization: Bearer ${PREFIX_API_KEY}" \
            "${server}/api/v1/delete/${channel}/${path}")
        if [[ "${code}" =~ ^2 ]]; then
            echo "deleted ${path}"
        else
            echo "::error::deleting ${path} failed with HTTP ${code}"
            status=1
        fi
    done < <(awk -v v="${version}" '$1 == v {print $2}' <<< "${files}")
done
exit "${status}"
