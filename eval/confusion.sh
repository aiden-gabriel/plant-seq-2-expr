#!/bin/bash
#SBATCH --job-name=confusion_matrix
#SBATCH --output=logs/confusion_matrix_%j.out
#SBATCH --error=logs/confusion_matrix_%j.err
#SBATCH --time=01:00:00
#SBATCH -A eecs
#SBATCH -p dgx2
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=256G

module load cuda/12.8

source /nfs/stak/users/gabrieai/hpc-share/miniconda3/etc/profile.d/conda.sh
conda activate nt

# --- Model checkpoints (fill in paths) ---
declare -A CHECKPOINTS=(
    ["zea_mays"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/zea_mays_2026-03-05_00-06-32/checkpoint-2250"
    ["oryza_sativa"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/oryza_sativa_2026-03-05_03-08-17/checkpoint-2500"
    ["solanum_lycopersicum"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/solanum_lycopersicum_2026-03-05_06-54-43/checkpoint-2125"
    ["glycine_max"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/glycine_max_original/checkpoint-4419"
    ["arabidopsis_thaliana"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/arabidopsis_original/checkpoint-4419"
)

dataset="pgb"  # Dataset name (must match keys in DATASET_NAMES in confusion_matrix.py)
N_SAMPLES=1000
BATCH_SIZE=4
SEED=42

# Threshold mode: uncomment ONE of the two options below.
# Option 1: percentile-based (default 33.3 / 66.7)
# THRESHOLD_ARGS="--percentiles 33.3 66.7"
# Option 2: fixed value thresholds
THRESHOLD_ARGS="--thresholds 1 25.0"

# Optional: restrict to a single tissue index (comment out to evaluate all tissues)
# TISSUE_ARGS="--tissue_idx 0"
TISSUE_ARGS=""

mkdir -p logs

for species in "${!CHECKPOINTS[@]}"; do
    checkpoint="${CHECKPOINTS[$species]}"

    if [ -z "$checkpoint" ]; then
        echo "Skipping $species — no checkpoint set"
        continue
    fi

    echo "Running confusion matrix for $species..."
    python confusion_matrix.py \
        --checkpoint "$checkpoint" \
        --dataset "$dataset" \
        --task_name  "$species" \
        --n_samples  "$N_SAMPLES" \
        --batch_size "$BATCH_SIZE" \
        --seed       "$SEED" \
        $THRESHOLD_ARGS \
        $TISSUE_ARGS \
        --output "confusion_matrix_${species}.png"
done
