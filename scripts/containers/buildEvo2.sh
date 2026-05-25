#!/usr/bin/env bash
# setupEvo2.sh — BioNeMo Evo2 setup using Apptainer

set -euo pipefail

# CUDA 12.8 is required to compile flash-attn v3 during the container build
CUDA_VERSION=$(module list 2>&1 | grep -oP "cuda/\K[0-9]+\.[0-9]+" || true)
if [[ -z "${CUDA_VERSION}" ]]; then
    echo ""
    echo "ERROR: No CUDA module loaded. Please run: module load cuda/12.8"
    echo ""
    exit 1
fi
if [[ "${CUDA_VERSION}" != "12.8" ]]; then
    echo ""
    echo "ERROR: CUDA 12.8 is required but found '${CUDA_VERSION}'"
    echo "Please run: module load cuda/12.8"
    echo ""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETED_DIR="${SCRIPT_DIR}/completed"
mkdir -p "${COMPLETED_DIR}"
TMP_DIR="${SCRIPT_DIR}/tmp/Evo2"
mkdir -p "${TMP_DIR}"
REPO_URL="https://github.com/NVIDIA/bionemo-framework.git"
CLONE_DIR="${TMP_DIR}"
SIF_PATH="${COMPLETED_DIR}/bionemo-evo2.sif"
DEF_FILE="${TMP_DIR}/bionemo-evo2.def"
BIONEMO_IMAGE="nvcr.io/nvidia/clara/bionemo-framework:2.6.1"

# 1. Clone the repo
echo ">>> Cloning bionemo-framework (main)..."
if [[ -d "${CLONE_DIR}/.git" ]]; then
    git -C "${CLONE_DIR}" fetch origin
    git -C "${CLONE_DIR}" checkout main
    git -C "${CLONE_DIR}" reset --hard "origin/main"
else
    git clone --single-branch --depth 1 "${REPO_URL}" "${CLONE_DIR}"
fi

# 2. Write definition file
echo ">>> Writing Apptainer definition file..."
cat > "${DEF_FILE}" << DEF
Bootstrap: docker
From: ${BIONEMO_IMAGE}

%files
    ${CLONE_DIR} /bionemo-src

%post
    pip install --no-build-isolation \
        -e /bionemo-src/sub-packages/bionemo-evo2/. 2>/dev/null || \
    pip install --no-build-isolation \
        -e /bionemo-src/. 2>/dev/null || true
    git clone https://github.com/Dao-AILab/flash-attention.git /tmp/flash-attention
    cd /tmp/flash-attention
    git checkout 27f501d
    cd hopper/
    python setup.py install
    python_path=\$(python -c 'import site; print(site.getsitepackages()[0])')
    mkdir -p \$python_path/flash_attn_3
    wget -q -P \$python_path/flash_attn_3 \
        https://raw.githubusercontent.com/Dao-AILab/flash-attention/27f501dbe011f4371bff938fe7e09311ab3002fa/hopper/flash_attn_interface.py

%environment
    export PYTHONNOUSERSITE=1
DEF

# 3. Build the custom image
echo ">>> Building custom Evo2 container (this will take a while)..."
APPTAINER_DOCKER_USERNAME='$oauthtoken' \
APPTAINER_DOCKER_PASSWORD="${NGC_API_KEY}" \
apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"

echo ">>> Cleaning up temporary files..."
rm -rf "${TMP_DIR}"

echo ""
echo "=== Done! ==="
echo ""