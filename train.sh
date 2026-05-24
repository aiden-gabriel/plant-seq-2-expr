#!/bin/bash
#SBATCH --job-name=arab_t_lora_test
#SBATCH --output=logs/arab_t_lora_test_%j.out
#SBATCH --error=logs/arab_t_lora_test_%j.err
#SBATCH --time=24:00:00
#SBATCH -A eecs
#SBATCH -p dgxh
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=256G

module load cuda/12.8

# Activate conda environment 
# ATTENTION ##################################################
source # [must add path to conda.sh here]
##############################################################
conda activate nt

model=agro_nt 
species=('arabidopsis_thaliana' 'solanum_lycopersicum' 'oryza_sativa' 'zea_mays' 'glycine_max')

# wandb
project=agro_r_test
group=group_1

# fine_tune
fine_tune_method=lora
lora_r=16
# lora_target_modules="query,value" #"intermediate.dense" and "output.dense"

for name in "${species[@]}"; do
    python train.py \
        --model_name $model \
        --task_name $name \
        --fine_tune_method $fine_tune_method \
        --lora_r $lora_r \
        --report_to "wandb" \
        --wandb_project $project \
        --wandb_group "$group" \
        --wandb_name "${name}" \
        --max_steps 3000 \
        --batch_size 32 
done
