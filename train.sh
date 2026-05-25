model=agro_nt 
species=('arabidopsis_thaliana' 'solanum_lycopersicum' 'oryza_sativa' 'zea_mays' 'glycine_max')

# wandb
project=agro_r_test
group=group_1

# fine_tune
fine_tune_method=lora
lora_r=16

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
