import os
import sys
import argparse
import numpy as np
import torch
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from datasets import load_dataset
from transformers import AutoTokenizer, AutoModelForSequenceClassification, DataCollatorWithPadding
from peft import PeftModel
from torch.utils.data import DataLoader

# Allow imports from project root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from utils.dataloader import load_data 

TASK_NAMES = [
    "glycine_max",
    "oryza_sativa",
    "solanum_lycopersicum",
    "zea_mays",
    "arabidopsis_thaliana",
]

BASE_MODEL = "InstaDeepAI/agro-nucleotide-transformer-1b"
DATASET_NAMES = {
    "pgb": "aiden-n-gabriel/pgb_exp_parquet"
}

BINS   = ["Low", "Med", "High"]
N_BINS = 3


def get_num_labels_from_checkpoint(checkpoint_path: str) -> int:
    """Infer num_labels from the saved classifier weight shape in the adapter checkpoint."""
    from safetensors import safe_open
    safetensors_path = os.path.join(checkpoint_path, "adapter_model.safetensors")
    with safe_open(safetensors_path, framework="pt") as f:
        keys = list(f.keys())
        # Find the output projection weight of the classifier/score head.
        # Newer checkpoints wrap it under modules_to_save.default; older ones save it directly.
        candidates = [k for k in keys if "weight" in k
                      and any(k.endswith(f"{h}.weight") for h in ("out_proj", "score"))]
        if not candidates:
            raise RuntimeError(
                f"Could not find classifier output weight in checkpoint. Keys found:\n{keys}"
            )
        # Among candidates, pick the one with the smallest first dim (that's num_labels)
        weights = {k: f.get_tensor(k) for k in candidates}
        best_key = min(weights, key=lambda k: weights[k].shape[0])
        weight = weights[best_key]
    return weight.shape[0]


def load_model_and_tokenizer(checkpoint_path: str):
    tokenizer = AutoTokenizer.from_pretrained(checkpoint_path)
    num_labels = get_num_labels_from_checkpoint(checkpoint_path)
    print(f"Inferred num_labels={num_labels} from checkpoint")
    base = AutoModelForSequenceClassification.from_pretrained(
        BASE_MODEL, num_labels=num_labels, ignore_mismatched_sizes=True
    )
    model = PeftModel.from_pretrained(base, checkpoint_path)
    model.eval()
    return model, tokenizer


def bucketize(values: np.ndarray, thresholds: tuple) -> np.ndarray:
    """Assign 0/1/2 (low/med/high) based on pre-computed thresholds."""
    lo, hi = thresholds
    buckets = np.where(values <= lo, 0, np.where(values <= hi, 1, 2))
    return buckets


def build_confusion_matrix(true_buckets: np.ndarray, pred_buckets: np.ndarray) -> np.ndarray:
    cm = np.zeros((N_BINS, N_BINS), dtype=int)
    for t, p in zip(true_buckets, pred_buckets):
        cm[t][p] += 1
    return cm


def plot_confusion_matrices(cms: list, tissue_names: list, task_name: str, out_path: str, samples: int, threshold_desc: str = ""):
    n = len(cms)
    cols = min(n, 4)
    rows = (n + cols - 1) // cols

    fig, axes = plt.subplots(rows, cols, figsize=(5 * cols, 4.5 * rows))
    axes = np.array(axes).flatten() if n > 1 else [axes]

    for i, (cm, tissue) in enumerate(zip(cms, tissue_names)):
        ax = axes[i]
        im = ax.imshow(cm, cmap="Blues")
        ax.set_xticks(range(N_BINS))
        ax.set_yticks(range(N_BINS))
        ax.set_xticklabels(BINS)
        ax.set_yticklabels(BINS)
        ax.set_xlabel("Predicted")
        ax.set_ylabel("True")
        ax.set_title(f"Tissue {tissue}")

        for r in range(N_BINS):
            for c in range(N_BINS):
                ax.text(c, r, str(cm[r, c]),
                        ha="center", va="center",
                        color="white" if cm[r, c] > cm.max() / 2 else "black")
        fig.colorbar(im, ax=ax)

    # Hide unused subplots
    for j in range(i + 1, len(axes)):
        axes[j].set_visible(False)

    fig.suptitle(f"Gene Expression Confusion Matrices — {task_name}\n(Low / Med / High, {threshold_desc}, n={samples} test samples)", y=1.02)
    plt.tight_layout()
    plt.savefig(out_path, bbox_inches="tight", dpi=150)
    print(f"Saved confusion matrix plot to: {out_path}")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=str, required=True,
                        help="Path to the saved checkpoint directory (e.g. runs/zea_mays_.../checkpoint-2250)")
    parser.add_argument("--task_name", type=str, required=True, choices=TASK_NAMES,
                        help="Plant species / task name")
    parser.add_argument("--dataset", type=str, default="pgb", choices=DATASET_NAMES.keys(),
                        help="Which dataset to use for evaluation (default: pgb)")
    parser.add_argument("--tissue_idx", type=int, default=None,
                        help="Single tissue index. If omitted, all tissues are evaluated.")
    parser.add_argument("--n_samples", type=int, default=None,
                        help="Number of test examples to sample. If omitted, uses the full test set.")
    parser.add_argument("--batch_size", type=int, default=4,
                        help="Inference batch size")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", type=str, default=None,
                        help="Output PNG path. Defaults to tests/confusion_matrix_<task>.png")

    threshold_group = parser.add_mutually_exclusive_group()
    threshold_group.add_argument("--thresholds", type=float, nargs=2, metavar=("LOW", "HIGH"),
                                 help="Fixed value thresholds for low/med/high (e.g. --thresholds 2.5 7.0). "
                                      "Applied to all tissues. Mutually exclusive with --percentiles.")
    threshold_group.add_argument("--percentiles", type=float, nargs=2, metavar=("LO_PCT", "HI_PCT"),
                                 default=[33.3, 66.7],
                                 help="Percentile thresholds computed from true labels per tissue "
                                      "(default: 33.3 66.7). Mutually exclusive with --thresholds.")

    args = parser.parse_args()

    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # --- Load model ---
    print(f"Loading model from: {args.checkpoint}")
    model, tokenizer = load_model_and_tokenizer(args.checkpoint)
    model.to(device)

    # --- Load test data ---
    data_path = DATASET_NAMES[args.dataset]
    print(f"Loading test data for task: {args.task_name} from dataset: {args.dataset}")
    test_data = load_data(data_path, task_name=args.task_name, split="test", tokenizer=tokenizer, tissue=args.tissue_idx)

    # --- Sample (optional) ---
    total = len(test_data)
    if args.n_samples is not None and args.n_samples < total:
        indices = np.random.choice(total, size=args.n_samples, replace=False)
        sampled = test_data.select(indices)
        print(f"Sampled {args.n_samples} / {total} test examples")
    else:
        sampled = test_data
        print(f"Using full test set: {total} examples")

    # --- Run inference ---
    sampled.set_format(type="torch", columns=["input_ids", "attention_mask", "labels"])
    collator = DataCollatorWithPadding(tokenizer=tokenizer)
    loader = DataLoader(sampled, batch_size=args.batch_size, collate_fn=collator)

    all_preds = []
    all_labels = []

    with torch.no_grad():
        for batch in loader:
            input_ids      = batch["input_ids"].to(device)
            attention_mask = batch["attention_mask"].to(device)
            labels         = batch["labels"]  # keep on CPU

            outputs = model(input_ids=input_ids, attention_mask=attention_mask)
            logits  = outputs.logits.cpu()

            all_preds.append(logits)
            all_labels.append(labels)

    # Shape: (n_samples,) for single tissue, or (n_samples, n_tissues) for multi-tissue
    all_preds  = torch.cat(all_preds,  dim=0).float().numpy()
    all_labels = torch.cat(all_labels, dim=0).float().numpy()

    # Squeeze single-output regression dim
    if all_preds.ndim == 2 and all_preds.shape[-1] == 1:
        all_preds  = all_preds.squeeze(-1)
        all_labels = all_labels.squeeze(-1)

    # --- Build per-tissue confusion matrices ---
    if all_labels.ndim == 1:
        # Single tissue
        tissue_indices = [0]
        preds_per_tissue  = [all_preds]
        labels_per_tissue = [all_labels]
    else:
        n_tissues = all_labels.shape[1]
        tissue_indices    = list(range(n_tissues))
        preds_per_tissue  = [all_preds[:, i]  for i in tissue_indices]
        labels_per_tissue = [all_labels[:, i] for i in tissue_indices]

    combined_cm  = np.zeros((N_BINS, N_BINS), dtype=int)

    for idx, (true_vals, pred_vals) in zip(tissue_indices, zip(labels_per_tissue, preds_per_tissue)):
        # Thresholds: fixed values or percentiles of true labels
        if args.thresholds is not None:
            lo, hi = args.thresholds
            threshold_desc = f"fixed thresholds"
        else:
            lo = np.percentile(true_vals, args.percentiles[0])
            hi = np.percentile(true_vals, args.percentiles[1])
            threshold_desc = f"percentile ({args.percentiles[0]}/{args.percentiles[1]})"

        true_buckets = bucketize(true_vals, (lo, hi))
        pred_buckets = bucketize(pred_vals, (lo, hi))

        cm = build_confusion_matrix(true_buckets, pred_buckets)
        combined_cm += cm

        label = str(args.tissue_idx) if args.tissue_idx is not None else str(idx)
        acc = np.sum(true_buckets == pred_buckets) / len(true_buckets)
        print(f"  Tissue {label} [{threshold_desc}]: low≤{lo:.3f}, high>{hi:.3f} | accuracy={acc:.3f}")

    overall_acc = np.diag(combined_cm).sum() / combined_cm.sum()
    print(f"\nCombined CM (all tissues):\n{combined_cm}")
    print(f"Overall accuracy: {overall_acc:.3f}")

    # --- Plot ---
    out_path = args.output or os.path.join(
        os.path.dirname(__file__),
        f"confusion_matrix_{args.task_name}.png"
    )
    threshold_desc = (
        f"fixed thresholds {args.thresholds[0]}/{args.thresholds[1]}"
        if args.thresholds is not None
        else f"percentiles {args.percentiles[0]}/{args.percentiles[1]}"
    )
    n_plotted = args.n_samples if args.n_samples is not None and args.n_samples < total else total
    plot_confusion_matrices([combined_cm], ["all tissues"], args.task_name, out_path, n_plotted, threshold_desc)


if __name__ == "__main__":
    main()
