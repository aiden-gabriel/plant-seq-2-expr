#!/usr/bin/env bash
# setupAgroNT.sh — AgroNT (Agro Nucleotide Transformer) setup using Apptainer
#
# AgroNT has no pre-built container — it is distributed via Hugging Face
# (InstaDeepAI/agro-nucleotide-transformer-1b). This script:
#   1. Clones the instadeepai/nucleotide-transformer repo
#   2. Builds a custom Apptainer image with all dependencies baked in
# Weights are downloaded automatically by HF on first use (~/.cache/huggingface)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETED_DIR="${SCRIPT_DIR}/completed"
mkdir -p "${COMPLETED_DIR}"
TMP_DIR="${SCRIPT_DIR}/tmp/AgroNT"
mkdir -p "${TMP_DIR}"
REPO_URL="https://github.com/instadeepai/nucleotide-transformer.git"
CLONE_DIR="${TMP_DIR}"
SIF_PATH="${COMPLETED_DIR}/agront.sif"
DEF_FILE="${TMP_DIR}/agront.def"

# 1. Clone the repo
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
From: nvcr.io/nvidia/pytorch:24.12-py3

%files
    ${CLONE_DIR} /agront-src

%post
    pip install --no-deps \
        "transformers<=4.40.0" \
        "huggingface_hub<1.0" \
        "tokenizers>=0.19,<0.20" \
        einops \
        "packaging<=24.2" \
        "six==1.16" \
        peft \
        accelerate \
        datasets \
        trl
    pip install --no-deps --use-pep517 -e /agront-src/.

%environment
    export PYTHONNOUSERSITE=1
DEF

# 3. Build the custom image
echo ">>> Building custom AgroNT container (this will take a while)..."
apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"

echo ">>> Cleaning up temporary files..."
rm -rf "${TMP_DIR}"

echo ""
echo "=== Done! ==="
echo ""