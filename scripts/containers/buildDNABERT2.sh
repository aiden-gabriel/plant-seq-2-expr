#!/usr/bin/env bash
# setupDNABERT2.sh — DNABERT-2 setup using Apptainer
#
# DNABERT-2 is distributed via HuggingFace (zhihan1996/DNABERT-2-117M).
# This script:
#   1. Clones the DNABERT-2 repo
#   2. Builds a custom Apptainer image with all dependencies baked in
# Weights are downloaded automatically by HF on first use (~/.cache/huggingface)
set -euo pipefail
# CUDA 12.8 is required to compile dependencies during the container build
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
TMP_DIR="${SCRIPT_DIR}/tmp/DNABERT2"
mkdir -p "${TMP_DIR}"
REPO_URL="https://github.com/MAGICS-LAB/DNABERT_2.git"
CLONE_DIR="${TMP_DIR}"
SIF_PATH="${COMPLETED_DIR}/dnabert2.sif"
DEF_FILE="${TMP_DIR}/dnabert2.def"
# 1. Clone the repo
echo ">>> Cloning DNABERT-2 repo..."
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
    ${CLONE_DIR} /dnabert2-src
%post
    pip install "flash-attn<3" --no-build-isolation
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
%environment
    mkdir -p /tmp/cuda-compat
    ln -sf /usr/local/cuda/compat/lib/libcuda.so.1 /tmp/cuda-compat/libcuda.so
    export LD_LIBRARY_PATH=/tmp/cuda-compat:/usr/local/cuda/compat/lib:\$LD_LIBRARY_PATH
    export PYTHONNOUSERSITE=1
DEF
# 3. Build the custom image
echo ">>> Building custom DNABERT-2 container (this will take a while)..."
apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"
echo ">>> Cleaning up temporary files..."
rm -rf "${TMP_DIR}"
echo ""
echo "=== Done! ==="
echo ""




# #!/usr/bin/env bash
# # setupDNABERT2.sh — DNABERT-2 setup using Apptainer
# #
# # DNABERT-2 is distributed via HuggingFace (zhihan1996/DNABERT-2-117M).
# # This script:
# #   1. Clones the DNABERT-2 repo
# #   2. Builds a custom Apptainer image with all dependencies baked in
# # Weights are downloaded automatically by HF on first use (~/.cache/huggingface)

# set -euo pipefail

# # CUDA 12.8 is required to compile dependencies during the container build
# CUDA_VERSION=$(module list 2>&1 | grep -oP "cuda/\K[0-9]+\.[0-9]+" || true)
# if [[ -z "${CUDA_VERSION}" ]]; then
#     echo ""
#     echo "ERROR: No CUDA module loaded. Please run: module load cuda/12.8"
#     echo ""
#     exit 1
# fi
# if [[ "${CUDA_VERSION}" != "12.8" ]]; then
#     echo ""
#     echo "ERROR: CUDA 12.8 is required but found '${CUDA_VERSION}'"
#     echo "Please run: module load cuda/12.8"
#     echo ""
#     exit 1
# fi

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# COMPLETED_DIR="${SCRIPT_DIR}/completed"
# mkdir -p "${COMPLETED_DIR}"
# TMP_DIR="${SCRIPT_DIR}/tmp/DNABERT2"
# mkdir -p "${TMP_DIR}"
# REPO_URL="https://github.com/MAGICS-LAB/DNABERT_2.git"
# CLONE_DIR="${TMP_DIR}"
# SIF_PATH="${COMPLETED_DIR}/dnabert2.sif"
# DEF_FILE="${TMP_DIR}/dnabert2.def"

# # 1. Clone the repo
# echo ">>> Cloning DNABERT-2 repo..."
# if [[ -d "${CLONE_DIR}/.git" ]]; then
#     git -C "${CLONE_DIR}" pull
# else
#     git clone --depth 1 "${REPO_URL}" "${CLONE_DIR}"
# fi

# # 2. Write definition file
# echo ">>> Writing Apptainer definition file..."
# cat > "${DEF_FILE}" << DEF
# Bootstrap: docker
# From: nvcr.io/nvidia/pytorch:24.12-py3

# %files
#     ${CLONE_DIR} /dnabert2-src

# %post
#     ln -sf /usr/local/cuda/compat/lib/libcuda.so.1 /usr/local/cuda/compat/lib/libcuda.so
#     pip install "flash-attn<3" --no-build-isolation
#     pip install --no-deps \
#         "transformers<=4.40.0" \
#         "huggingface_hub<1.0" \
#         "tokenizers>=0.19,<0.20" \
#         einops \
#         "packaging<=24.2" \
#         "six==1.16" \
#         peft \
#         accelerate \
#         datasets \
#         trl

# %environment
#     export LD_LIBRARY_PATH=/usr/local/cuda/compat/lib:\$LD_LIBRARY_PATH
#     export PYTHONNOUSERSITE=1
# DEF

# # 3. Build the custom image
# echo ">>> Building custom DNABERT-2 container (this will take a while)..."
# apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"

# echo ">>> Cleaning up temporary files..."
# rm -rf "${TMP_DIR}"

# echo ""
# echo "=== Done! ==="
# echo ""