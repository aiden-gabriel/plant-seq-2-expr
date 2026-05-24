import os
import json
from transformers import AutoTokenizer, AutoModelForMaskedLM, TrainingArguments, Trainer, TrainerCallback, AutoModelForSequenceClassification
from datetime import datetime
import torch
import gc
from sklearn.metrics import r2_score
from sklearn.model_selection import train_test_split
from datasets import load_dataset, Dataset
import numpy as np
import argparse
import csv
import wandb

import matplotlib.pyplot as plt

from utils.dataloader import load_data
from utils.get_model_for_training import get_model


model_names = {
    "agro_nt": "InstaDeepAI/agro-nucleotide-transformer-1b"
}

dataset_names = {
    "pgb": "aiden-n-gabriel/pgb_exp_parquet"
}

fine_tune_methods = [
    "lora",
    # "full_fine_tuning",
    # "head_only", # maybe in the future
]

task_names=[
    'glycine_max',
    'oryza_sativa',
    'solanum_lycopersicum',
    'zea_mays',
    'arabidopsis_thaliana',
]


class SaveMetadataCallback(TrainerCallback):
    """Writes training_metadata.json into every checkpoint directory as it is saved."""
    def __init__(self, metadata: dict):
        self.metadata = metadata

    def on_save(self, args, state, control, **kwargs):
        checkpoint_dir = os.path.join(args.output_dir, f"checkpoint-{state.global_step}")
        os.makedirs(checkpoint_dir, exist_ok=True)
        with open(os.path.join(checkpoint_dir, "training_metadata.json"), "w") as f:
            json.dump(self.metadata, f, indent=2)


def compute_r2(eval_pred):
    predictions, labels = eval_pred

    # Squeeze the last dimension if it exists (for single output regression tasks)
    if predictions.ndim == 2 and predictions.shape[-1] == 1:
        predictions = predictions.squeeze(-1)
    if labels.ndim == 2 and labels.shape[-1] == 1:
        labels = labels.squeeze(-1)

    r2 = r2_score(labels, predictions)
    return {"r2_score": r2}


def save_results(test_results, tissue_idx, output_dir, report_to):
    preds = test_results.predictions  # (n_samples, num_labels)
    labels = test_results.label_ids   # (n_samples, num_labels)
    if preds.ndim == 1:
        preds = preds[:, np.newaxis]
    if labels.ndim == 1:
        labels = labels[:, np.newaxis]

    rows = []
    for i in range(preds.shape[1]):
        idx = tissue_idx if tissue_idx is not None else i
        rows.append({"idx": idx, "r2_score": r2_score(labels[:, i], preds[:, i])})
    overall_r2 = r2_score(labels.ravel(), preds.ravel())
    rows.append({"idx": "all", "r2_score": overall_r2})

    print(f"R2 score on the test dataset: {overall_r2}")
    if report_to == "wandb":
        wandb.log({"test/r2_score": overall_r2})
        wandb.finish()

    with open(os.path.join(output_dir, "results.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["idx", "r2_score"])
        writer.writeheader()
        writer.writerows(rows)


def main():
    now = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    
    parser = argparse.ArgumentParser()

    parser.add_argument("--model_name", type=str, default="agro_nt", help="Model name or path")
    parser.add_argument("--dataset", type=str, default="pgb", help="Dataset name or path")
    parser.add_argument("--task_name", type=str, default="arabidopsis_thaliana", help="Task name within the dataset")
    parser.add_argument("--tissue_idx", type=int, default=None, help="Index of the tissue to use for training (e.g., 0 for leaf, 1 for root, etc.). If not specified, uses all tissues.") # Allows for training single tissue models

    parser.add_argument("--fine_tune_method", type=str, default="lora", help="Fine-tuning method to use (e.g., 'lora', 'full_fine_tuning'(not implemented yet), (maybe in future: 'frozen'))")
    parser.add_argument("--lora_r", type=int, default=8, help="LoRA rank (only used if --fine_tune_method is 'lora')")
    parser.add_argument("--lora_alpha", type=int, default=None, help="LoRA alpha, default set to 2*lora_r later (only used if --fine_tune_method is 'lora')")
    parser.add_argument("--lora_dropout", type=float, default=0.1, help="LoRA dropout rate (only used if --fine_tune_method is 'lora')")
    parser.add_argument("--lora_target_modules", type=str, default="query,value", help="Comma-separated list of module names to apply LoRA to. AgroNT Options: query, key, intermediate.dense, output.dense (only used if --fine_tune_method is 'lora')")

    parser.add_argument("--batch_size", type=int, default=32, help="Batch size for training and evaluation")
    parser.add_argument("--num_epochs", type=int, default=3, help="Number of training epochs")
    parser.add_argument("--max_steps", type=int, default=-1, help="Maximum number of training steps. Overrides --num_epochs if set to a positive value.")
    parser.add_argument("--learning_rate", type=float, default=5e-4, help="Learning rate for training")

    parser.add_argument("--num_log_steps", type=int, default=100, help="Number of times to log training metrics during the entire training process (e.g., 100 means logging every 1% of the training steps)")
    parser.add_argument("--num_eval_steps", type=int, default=20, help="Number of times to evaluate the model on the validation set during the entire training process (e.g., 20 means evaluating every 5% of the training steps)")
    parser.add_argument("--num_save_steps", type=int, default=20, help="Number of times to save the model during the entire training process (e.g., 20 means saving every 5% of the training steps)")
    parser.add_argument("--output_dir", type=str, default="runs", help="Local directory to save the best model at the end of training")
    
    parser.add_argument("--report_to", type=str, default="none", help="The integration to report the results and logs to. Supported platforms are: 'tensorboard', 'wandb' and 'comet_ml'. Use 'none' for no logging.")
    parser.add_argument("--wandb_project", type=str, default=None, help="WandB project name")
    parser.add_argument("--wandb_group", type=str, default=None, help="WandB group name (e.g., for grouping runs by task)")
    parser.add_argument("--wandb_name", type=str, default=None, help="WandB run name (e.g., for identifying specific runs)")
    
    args = parser.parse_args()

    # Argument Validation
    if args.model_name not in model_names:
        raise ValueError(f"Invalid model name: {args.model_name}. Must be one of {list(model_names.keys())}.")
    if args.fine_tune_method not in fine_tune_methods:
        raise ValueError(f"Invalid fine-tuning method: {args.fine_tune_method}. Must be one of {fine_tune_methods}.")
    if args.task_name not in task_names:
        raise ValueError(f"Invalid task name: {args.task_name}. Must be one of {task_names}.")

    # Argument Clean Up
    if args.fine_tune_method == "lora":
        if args.lora_alpha is None:
            args.lora_alpha = args.lora_r * 2
        args.lora_target_modules = args.lora_target_modules.split(",")

    if args.report_to == "wandb":
        if args.wandb_project is None:
            args.wandb_project = f"{args.model_name}_seq2expr"
        if args.wandb_group is None:
            args.wandb_group = args.task_name
        if args.wandb_name is None:
            if args.tissue_idx is not None:
                args.wandb_name = f"{args.task_name}_tissue_{args.tissue_idx}_{now}"
            else:
                args.wandb_name = f"{args.task_name}_{now}" 
        wandb.init(
            project=args.wandb_project,
            group=args.wandb_group,
            name=args.wandb_name,
            config={
                "model_name": args.model_name,
                "dataset": args.dataset,
                "task_name": args.task_name,
                "tissue_idx": args.tissue_idx if args.tissue_idx is not None else "all",
                "batch_size": args.batch_size,
                "num_epochs": args.num_epochs,
                "max_steps": args.max_steps,
                "learning_rate": args.learning_rate,
                "fine_tune_method": args.fine_tune_method,
                "lora_rank": args.lora_r if args.fine_tune_method == "lora" else None,
                "lora_alpha": args.lora_alpha if args.fine_tune_method == "lora" else None,
                "lora_dropout": args.lora_dropout if args.fine_tune_method == "lora" else None,
                "lora_target_modules": args.lora_target_modules if args.fine_tune_method == "lora" else None,
            },
        )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    model_name = model_names[args.model_name]
    data_path = dataset_names[args.dataset]

    tokenizer = AutoTokenizer.from_pretrained(model_name)
    train_data = load_data(data_path, task_name=args.task_name, split="train", tokenizer=tokenizer , tissue=args.tissue_idx)
    val_data = load_data(data_path, task_name=args.task_name, split="validation", tokenizer=tokenizer, tissue=args.tissue_idx,)
    test_data = load_data(data_path, task_name=args.task_name, split="test", tokenizer=tokenizer, tissue=args.tissue_idx)
    
    num_labels = len(train_data[0]["labels"])
    print(f"Number of labels: {num_labels}")

    model = get_model(model_name, num_labels, args.fine_tune_method, args.lora_r, args.lora_alpha, args.lora_dropout, args.lora_target_modules)
    model.to(device) # Put the model on the GPU

    total_steps = args.max_steps if args.max_steps > 0 else (len(train_data) * args.num_epochs) // args.batch_size

    if args.tissue_idx is not None:
        output_dir = f"{args.output_dir}/{args.task_name}_tissue_{args.tissue_idx}_{now}"
    else:
        output_dir = f"{args.output_dir}/{args.task_name}_{now}"
    os.makedirs(output_dir, exist_ok=True)

    training_metadata = {
        "base_model":        args.model_name,
        "base_model_path":   model_name,
        "dataset":           args.dataset,
        "task_name":         args.task_name,
        "tissue_idx":        args.tissue_idx if args.tissue_idx is not None else "all",
        "num_labels":        num_labels,
        "timestamp":         now,
        "total_training_steps": total_steps,
        "batch_size":        args.batch_size,
        "learning_rate":     args.learning_rate,
        "fine_tune_method":  args.fine_tune_method,
        "lora_rank":         args.lora_r if args.fine_tune_method == "lora" else None,
        "lora_alpha":        args.lora_alpha if args.fine_tune_method == "lora" else None,
        "lora_dropout":      args.lora_dropout if args.fine_tune_method == "lora" else None,
        "lora_target_modules": args.lora_target_modules if args.fine_tune_method == "lora" else None,   
    }

    training_args = TrainingArguments(
        output_dir=output_dir,
        remove_unused_columns=False,
        eval_strategy="steps",
        save_strategy="steps",
        logging_strategy="steps",
        logging_steps=max(1, total_steps // args.num_log_steps),
        save_steps=max(1, total_steps // args.num_save_steps),
        eval_steps=max(1, total_steps // args.num_eval_steps),
        num_train_epochs=args.num_epochs,
        max_steps=args.max_steps,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size,
        load_best_model_at_end=True,
        save_total_limit=1,
        learning_rate=args.learning_rate,
        metric_for_best_model="r2_score",
        label_names=["labels"],
        report_to=args.report_to,
        skip_memory_metrics=False,

        # Memory efficiency settings
        bf16=True,        
        gradient_accumulation_steps= 1,
        gradient_checkpointing=True,      
        optim="adamw_torch_fused",  
    )

    print(f"Learning rate: {training_args.learning_rate}")

    # Starting Training
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_data,
        eval_dataset=val_data,
        processing_class=tokenizer,
        compute_metrics=compute_r2,
        callbacks=[SaveMetadataCallback(training_metadata)],
    )

    train_results = trainer.train()
    test_results = trainer.predict(test_data)

    if args.max_steps > 0:
        args.num_epochs = (args.max_steps * args.batch_size) // len(train_data)

    save_results(test_results, args.tissue_idx, output_dir, args.report_to)


if __name__ == "__main__":
    main()