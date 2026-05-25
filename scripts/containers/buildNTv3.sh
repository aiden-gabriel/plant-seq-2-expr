#!/usr/bin/env bash
# setupNTv3.sh — Nucleotide Transformer v3 (NTv3) setup using Apptainer
#
# NTv3 has no pre-built container — it is distributed via Hugging Face
# (InstaDeepAI/NTv3_*). This script:
#   1. Clones the instadeepai/nucleotide-transformer repo (shared with AgroNT)
#   2. Builds a custom Apptainer image with all dependencies baked in
# Weights are downloaded automatically by HF on first use (~/.cache/huggingface)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETED_DIR="${SCRIPT_DIR}/completed"
mkdir -p "${COMPLETED_DIR}"
TMP_DIR="${SCRIPT_DIR}/tmp/NTv3"
mkdir -p "${TMP_DIR}"
REPO_URL="https://github.com/instadeepai/nucleotide-transformer.git"
CLONE_DIR="${TMP_DIR}"
SIF_PATH="${COMPLETED_DIR}/ntv3.sif"
DEF_FILE="${TMP_DIR}/ntv3.def"
BASE_IMAGE="nvcr.io/nvidia/pytorch:24.12-py3"
# 1. Clone the repo (reuse existing clone if present — shared with AgroNT)
echo ">>> Cloning nucleotide-transformer repo..."
if [[ -d "${CLONE_DIR}/.git" ]]; then
    git -C "${CLONE_DIR}" pull
else
    git clone --depth 1 "${REPO_URL}" "${CLONE_DIR}"
fi
# 2. Write definition file
echo ">>> Writing Apptainer definition file..."
cat > "${DEF_FILE}" << DEF
Bootstrap: docker
From: ${BASE_IMAGE}
%files
    ${CLONE_DIR} /ntv3-src
%post
    pip install \
        "transformers>=4.46.0" \
        "huggingface_hub>=0.25" \
        einops \
        "packaging<=24.2" \
        "six==1.16" \
        peft \
        accelerate \
        datasets \
        trl
    pip install --no-deps --use-pep517 -e /ntv3-src/.
%environment
    export PYTHONNOUSERSITE=1
DEF
# 3. Build the custom image
echo ">>> Building custom NTv3 container (this will take a while)..."
apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"
echo ">>> Cleaning up temporary files..."
rm -rf "${TMP_DIR}"
echo ""
echo "=== Done! ==="
echo ""