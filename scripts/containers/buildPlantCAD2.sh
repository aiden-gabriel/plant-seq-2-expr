#!/usr/bin/env bash
# setupPlantCAD2.sh — PlantCAD2 setup using Apptainer
#
# PlantCAD2 has no pre-built container — it is distributed via Hugging Face
# (kuleshov-group/PlantCAD2-Small-*, PlantCAD2-Medium-*, PlantCAD2-Large-*).
# This script:
#   1. Clones the plantcad/plantcad repo
#   2. Builds a custom Apptainer image with all dependencies baked in
# Weights are downloaded automatically by HF on first use (~/.cache/huggingface)
#
# NOTE: mamba-ssm builds from source — this step takes ~10-15 minutes.
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
TMP_DIR="${SCRIPT_DIR}/tmp/PlantCAD2"
mkdir -p "${TMP_DIR}"

REPO_URL="https://github.com/plantcad/plantcad.git"
CLONE_DIR="${TMP_DIR}"
SIF_PATH="${COMPLETED_DIR}/plantcad2.sif"
DEF_FILE="${TMP_DIR}/plantcad2.def"
BASE_IMAGE="nvcr.io/nvidia/pytorch:24.12-py3"

# 1. Clone the repo
echo ">>> Cloning plantcad repo..."
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
    ${CLONE_DIR} /plantcad-src

%post
    # Install plantcad's pinned dependencies from its requirements.txt.
    # Note: torch/torchvision/torchaudio are already in the NGC base image
    # and are NOT reinstalled here to avoid breaking the CUDA-optimised build.
    pip install \
        "transformers==4.49.0" \
        "peft==0.14.0" \
        "datasets==3.3.2" \
        "pandas==2.2.3" \
        "scipy==1.12.0" \
        "biopython" \
        "xgboost==2.0.3" \
        "scikit-learn==1.4.0" \
        "matplotlib" \
        "fire==0.7.0" \
        "tqdm" \
        "einops" \
        "accelerate" \
        "trl" \
        "git+https://github.com/dridk/PyVCF3.git@1.0.4"

    # --no-build-isolation is required so that the mamba-ssm and causal-conv1d
    # build subprocesses can see the PyTorch already installed in the NGC base
    # image. Without it, pip's isolated build environment has no 'torch' and
    # the source compilation fails immediately.
    pip install --no-build-isolation causal-conv1d mamba-ssm

    # Register the CUDA compat lib path with ldconfig so that both the runtime
    # linker (ld.so) and gcc's compile-time linker can find libcuda.so.1.
    # Without this, triton fails to initialise when running under Apptainer --nv
    # because the NGC container puts libcuda in the compat path which is not
    # searched by default.
    echo '/usr/local/cuda/compat/lib' > /etc/ld.so.conf.d/cuda-compat.conf
    ldconfig

%environment
    export PYTHONNOUSERSITE=1
    # The plantcad repo is not a pip-installable package (no setup.py /
    # pyproject.toml). Add both the repo root and its src/ subdirectory
    # to PYTHONPATH so all modules are importable at runtime.
    export PYTHONPATH=/plantcad-src:/plantcad-src/src:\${PYTHONPATH:-}
    # Make libcuda.so.1 findable at runtime for both ld.so and gcc/triton
    # kernel compilation (triton JIT-compiles CUDA kernels on first use).
    export LD_LIBRARY_PATH=/usr/local/cuda/compat/lib:\${LD_LIBRARY_PATH:-}
DEF

# 3. Build the custom image
echo ">>> Building custom PlantCAD2 container (mamba-ssm builds from source, ~10-15 min)..."
apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"

echo ">>> Cleaning up temporary files..."
rm -rf "${TMP_DIR}"

echo ""
echo "=== Done! ==="
echo ""



# #!/usr/bin/env bash
# # setupPlantCAD2.sh — PlantCAD2 setup using Apptainer
# #
# # PlantCAD2 has no pre-built container — it is distributed via Hugging Face
# # (kuleshov-group/PlantCAD2-Small-*, PlantCAD2-Medium-*, PlantCAD2-Large-*).
# # This script:
# #   1. Clones the plantcad/plantcad repo
# #   2. Builds a custom Apptainer image with all dependencies baked in
# # Weights are downloaded automatically by HF on first use (~/.cache/huggingface)
# #
# # NOTE: mamba-ssm builds from source — this step takes ~10-15 minutes.
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
# TMP_DIR="${SCRIPT_DIR}/tmp/PlantCAD2"
# mkdir -p "${TMP_DIR}"

# REPO_URL="https://github.com/plantcad/plantcad.git"
# CLONE_DIR="${TMP_DIR}"
# SIF_PATH="${COMPLETED_DIR}/plantcad2.sif"
# DEF_FILE="${TMP_DIR}/plantcad2.def"
# BASE_IMAGE="nvcr.io/nvidia/pytorch:24.12-py3"

# # 1. Clone the repo
# echo ">>> Cloning plantcad repo..."
# if [[ -d "${CLONE_DIR}/.git" ]]; then
#     git -C "${CLONE_DIR}" pull
# else
#     git clone --depth 1 "${REPO_URL}" "${CLONE_DIR}"
# fi

# # 2. Write definition file
# echo ">>> Writing Apptainer definition file..."
# cat > "${DEF_FILE}" << DEF
# Bootstrap: docker
# From: ${BASE_IMAGE}

# %files
#     ${CLONE_DIR} /plantcad-src

# %post
#     # Install plantcad's pinned dependencies from its requirements.txt.
#     # Note: torch/torchvision/torchaudio are already in the NGC base image
#     # and are NOT reinstalled here to avoid breaking the CUDA-optimised build.
#     pip install \
#         "transformers==4.49.0" \
#         "peft==0.14.0" \
#         "datasets==3.3.2" \
#         "pandas==2.2.3" \
#         "scipy==1.12.0" \
#         "biopython" \
#         "xgboost==2.0.3" \
#         "scikit-learn==1.4.0" \
#         "matplotlib" \
#         "fire==0.7.0" \
#         "tqdm" \
#         "einops" \
#         "accelerate" \
#         "trl" \
#         "git+https://github.com/dridk/PyVCF3.git@1.0.4"

#     # --no-build-isolation is required so that the mamba-ssm and causal-conv1d
#     # build subprocesses can see the PyTorch already installed in the NGC base
#     # image. Without it, pip's isolated build environment has no 'torch' and
#     # the source compilation fails immediately.
#     pip install --no-build-isolation causal-conv1d mamba-ssm

# %environment
#     export PYTHONNOUSERSITE=1
#     # The plantcad repo is not a pip-installable package (no setup.py /
#     # pyproject.toml). Add both the repo root and its src/ subdirectory
#     # to PYTHONPATH so all modules are importable at runtime.
#     export PYTHONPATH=/plantcad-src:/plantcad-src/src:\${PYTHONPATH:-}
# DEF

# # 3. Build the custom image
# echo ">>> Building custom PlantCAD2 container (mamba-ssm builds from source, ~10-15 min)..."
# apptainer build --fakeroot "${SIF_PATH}" "${DEF_FILE}"

# echo ">>> Cleaning up temporary files..."
# rm -rf "${TMP_DIR}"

# echo ""
# echo "=== Done! ==="
# echo ""