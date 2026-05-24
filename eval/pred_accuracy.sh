#!/bin/bash
#SBATCH --job-name=pred_accuracy
#SBATCH --output=logs/pred_accuracy_%j.out
#SBATCH --error=logs/pred_accuracy_%j.err
#SBATCH --time=12:00:00
#SBATCH -A eecs
#SBATCH -p dgx2
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=256G

module load cuda/12.8

source /nfs/stak/users/gabrieai/hpc-share/miniconda3/etc/profile.d/conda.sh
conda activate nt

# --- Model checkpoints ---
declare -A CHECKPOINTS=(
    ["zea_mays"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/zea_mays_2026-03-05_00-06-32/checkpoint-2250"
    ["oryza_sativa"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/oryza_sativa_2026-03-05_03-08-17/checkpoint-2500"
    ["solanum_lycopersicum"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/solanum_lycopersicum_2026-03-05_06-54-43/checkpoint-2125"
    ["glycine_max"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/glycine_max_original/checkpoint-4419"
    ["arabidopsis_thaliana"]="/nfs/stak/users/gabrieai/hpc-share/genomics/CS46X_Project/seq-2-expr/runs/arabidopsis_original/checkpoint-4419"
)

DATASET="pgb"
# N_SAMPLES=500
BATCH_SIZE=4
SEED=42

# Optional: restrict to a single tissue index (comment out to average all tissues)
# TISSUE_ARGS="--tissue_idx 0"
TISSUE_ARGS=""

mkdir -p logs

for species in "${!CHECKPOINTS[@]}"; do
    checkpoint="${CHECKPOINTS[$species]}"

    if [ -z "$checkpoint" ]; then
        echo "Skipping $species — no checkpoint set"
        continue
    fi

    echo "Running prediction accuracy plots for $species..."
    python pred_accuracy.py \
        --checkpoint "$checkpoint" \
        --dataset    "$DATASET" \
        --task_name  "$species" \
        --batch_size "$BATCH_SIZE" \
        --seed       "$SEED" \
        --out_dir    "pred_accuracy_min_0" \
        $TISSUE_ARGS
done
