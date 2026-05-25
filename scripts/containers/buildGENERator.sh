#!/usr/bin/env bash
# setupGENERator.sh — GENERator genomic foundation model setup using Apptainer
#
# GENERator has no pre-built container — it is distributed via Hugging Face
# (GenerTeam/GENERator-eukaryote-1.2b-base, GenerTeam/GENERator-eukaryote-3b-base)
# This script:
#   1. Clones the GenerTeam/GENERator repo
#   2. Builds a custom Apptainer image with all dependencies baked in
# Weights are downloaded automatically by HF on first use (~/.cache/huggingface)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETED_DIR="${SCRIPT_DIR}/completed"
mkdir -p "${COMPLETED_DIR}"

TMP_DIR="${SCRIPT_DIR}/tmp/GENERator"
mkdir -p "${TMP_DIR}"

REPO_URL="https://github.com/GenerTeam/GENERator.git"
CLONE_DIR="${TMP_DIR}"
SIF_PATH="${COMPLETED_DIR}/generator.sif"
DEF_FILE="${TMP_DIR}/generator.def"

# 1. Clone the repo
echo ">>> Cloning GENERator repo..."
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
    ${CLONE_DIR} /generator-src

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
    # No pip install — repo has no setup.py/pyproject.toml

%environment
    export PYTHONNOUSERSITE=1
    export PYTHONPATH=/generator-src:\${PYTHONPATH:-}
DEF

# 3. Build the custom image
echo ">>> Building custom GENERator container (this will take a while)..."
apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"

echo ">>> Cleaning up temporary files..."
rm -rf "${TMP_DIR}"

echo ""
echo "=== Done! ==="
echo ""