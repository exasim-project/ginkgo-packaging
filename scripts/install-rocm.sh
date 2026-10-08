#!/usr/bin/env bash
# Installs the parts of ROCm Ginkgo's HIP backend needs from AMD's apt
# repository into /opt/rocm. Used by the experimental ROCm conda build, which
# cannot get hipBLAS & co. from conda-forge. Ubuntu 24.04 (noble) only.
#   install-rocm.sh [rocm version, default 6.4.4]
set -euo pipefail

version="${1:-6.4.4}"
sudo=""
if [[ "$(id -u)" != "0" ]]; then
    sudo="sudo"
fi

${sudo} mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key \
    | gpg --dearmor | ${sudo} tee /etc/apt/keyrings/rocm.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${version} noble main" \
    | ${sudo} tee /etc/apt/sources.list.d/rocm.list
printf 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600\n' \
    | ${sudo} tee /etc/apt/preferences.d/rocm-pin-600

${sudo} apt-get update
${sudo} apt-get install -y --no-install-recommends \
    hipcc rocm-llvm rocm-cmake rocm-device-libs hip-dev hip-runtime-amd \
    hipblas-dev hipsparse-dev hiprand-dev hipfft-dev \
    rocthrust-dev rocprim-dev hipcub-dev roctracer-dev

/opt/rocm/bin/hipconfig --version
