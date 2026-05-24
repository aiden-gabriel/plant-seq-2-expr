import os
import sys
import argparse
import json
import numpy as np
import torch
import matplotlib.pyplot as plt
from scipy.stats import pearsonr
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

def iqr_upper_fence(vals: np.ndarray) -> float:
    """Return Q3 + 1.5*IQR as the highest non-outlier threshold."""
    q1, q3 = np.percentile(vals, [25, 75])
    return q3 + 1.5 * (q3 - q1)


def make_bins(true_vals: np.ndarray):
    """Build integer bin edges from 0 up to floor(IQR fence)+1.
    Only bins with at least one true value are returned."""
    fence = iqr_upper_fence(true_vals)
    max_bin = int(np.floor(fence)) + 1
    edges  = list(range(max_bin + 1))          # [0, 1, 2, ..., max_bin]
    labels = [f"{i}-{i+1}" for i in range(max_bin)]
    return edges, labels


def get_num_labels_from_checkpoint(checkpoint_path: str) -> int:
    from safetensors import safe_open
    safetensors_path = os.path.join(checkpoint_path, "adapter_model.safetensors")
    with safe_open(safetensors_path, framework="pt") as f:
        keys = list(f.keys())
        candidates = [k for k in keys if "weight" in k
                      and any(k.endswith(f"{h}.weight") for h in ("out_proj", "score"))]
        if not candidates:
            raise RuntimeError(
                f"Could not find classifier output weight in checkpoint. Keys found:\n{keys}"
            )
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


def plot_boxplot(true_vals: np.ndarray, pred_vals: np.ndarray, task_name: str, out_path: str):
    """Box plot: x-axis = true TPM integer bins, y-axis = predicted TPM.
    Bins are dynamic: only integer ranges that have data and fall within the
    IQR fence of true values are shown. Outliers rendered as individual dots."""
    bin_edges, bin_labels = make_bins(true_vals)
    # np.digitize with bin_edges[1:-1] as boundaries assigns index 0 to values < edges[1], etc.
    bin_indices = np.digitize(true_vals, bin_edges[1:-1])

    grouped_preds = []
    tick_labels   = []
    for i in range(len(bin_labels)):
        mask = bin_indices == i
        if not mask.any():
            continue  # skip empty bins
        grouped_preds.append(pred_vals[mask])
        tick_labels.append(f"{bin_labels[i]}\n(n={mask.sum()})")

    fig, ax = plt.subplots(figsize=(max(10, len(grouped_preds) * 1.4), 6))
    bp = ax.boxplot(
        grouped_preds,
        patch_artist=True,
        showfliers=True,
        whis=1.5,
        flierprops=dict(marker="o", markersize=2, linestyle="none",
                        markerfacecolor="steelblue", markeredgecolor="none", alpha=0.4),
    )

    for patch in bp["boxes"]:
        patch.set_facecolor("steelblue")
        patch.set_alpha(0.7)

    ax.set_xticks(range(1, len(grouped_preds) + 1))
    ax.set_xticklabels(tick_labels, fontsize=8)
    ax.set_xlabel("True Gene Expression (TPM)")
    ax.set_ylabel("Predicted TPM")
    ax.set_title(f"Predicted vs True TPM — {task_name}")
    plt.tight_layout()
    plt.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Saved box plot to: {out_path}")
    plt.close(fig)


def save_summary_stats(true_vals: np.ndarray, pred_vals: np.ndarray, task_name: str, out_path: str):
    """Save per-bin and overall summary statistics to a JSON file."""
    bin_edges, bin_labels = make_bins(true_vals)
    bin_indices = np.digitize(true_vals, bin_edges[1:-1])

    per_bin = []
    for i, label in enumerate(bin_labels):
        mask = bin_indices == i
        true_bin = true_vals[mask]
        pred_bin = pred_vals[mask]
        n = int(mask.sum())
        if n == 0:
            per_bin.append({"bin": label, "n": 0})
            continue
        per_bin.append({
            "bin": label,
            "n": n,
            "true_mean":  round(float(true_bin.mean()),  4),
            "pred_mean":  round(float(pred_bin.mean()),  4),
            "pred_median":round(float(np.median(pred_bin)), 4),
            "pred_std":   round(float(pred_bin.std()),   4),
            "pred_q25":   round(float(np.percentile(pred_bin, 25)), 4),
            "pred_q75":   round(float(np.percentile(pred_bin, 75)), 4),
            "mae":        round(float(np.abs(true_bin - pred_bin).mean()), 4),
        })

    mae  = float(np.abs(true_vals - pred_vals).mean())
    rmse = float(np.sqrt(((true_vals - pred_vals) ** 2).mean()))
    ss_res = float(((true_vals - pred_vals) ** 2).sum())
    ss_tot = float(((true_vals - true_vals.mean()) ** 2).sum())
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else float("nan")
    r, _ = pearsonr(true_vals, pred_vals)

    stats = {
        "task_name": task_name,
        "n_samples": int(len(true_vals)),
        "overall": {
            "mae":          round(mae,  4),
            "rmse":         round(rmse, 4),
            "r2":           round(r2,   4),
            "pearson_r":    round(float(r), 4),
            "true_mean":    round(float(true_vals.mean()),  4),
            "true_std":     round(float(true_vals.std()),   4),
            "pred_mean":    round(float(pred_vals.mean()),  4),
            "pred_std":     round(float(pred_vals.std()),   4),
        },
        "per_bin": per_bin,
    }

    with open(out_path, "w") as f:
        json.dump(stats, f, indent=2)
    print(f"Saved summary stats to: {out_path}")


def plot_histogram(vals: np.ndarray, label: str, task_name: str, out_path: str, color: str):
    """Histogram clipped to the highest non-outlier value (Q3 + 1.5*IQR).
    A note in the corner reports how many values fell above the cutoff."""
    cutoff = iqr_upper_fence(vals)
    n_outliers = int((vals > cutoff).sum())
    clipped = vals[vals <= cutoff]

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.hist(clipped, bins=50, color=color, alpha=0.75, edgecolor="white")
    ax.set_xlabel("TPM")
    ax.set_ylabel("Count")
    ax.set_title(f"{label} TPM Distribution — {task_name}")
    ax.text(0.98, 0.97,
            f"Outliers excluded: {n_outliers} ({100 * n_outliers / len(vals):.1f}%)\n(> {cutoff:.2f} TPM)",
            transform=ax.transAxes, fontsize=8, va="top", ha="right",
            bbox=dict(boxstyle="round,pad=0.3", facecolor="lightyellow", edgecolor="gray", alpha=0.8))
    plt.tight_layout()
    plt.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Saved {label.lower()} histogram to: {out_path}")
    plt.close(fig)


def plot_combined_histogram(true_vals: np.ndarray, pred_vals: np.ndarray, task_name: str, out_path: str):
    """Overlaid histogram of true and predicted TPM.
    X-axis upper limit is the max non-outlier fence across both distributions.
    A note reports how many values from each series fall outside the plot."""
    true_fence = iqr_upper_fence(true_vals)
    pred_fence = iqr_upper_fence(pred_vals)
    cutoff = max(true_fence, pred_fence)

    n_true_out = int((true_vals > cutoff).sum())
    n_pred_out = int((pred_vals > cutoff).sum())

    bins = np.linspace(0, cutoff, 51)

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.hist(true_vals[true_vals <= cutoff], bins=bins, color="steelblue",  alpha=0.6, label="True",      edgecolor="white")
    ax.hist(pred_vals[pred_vals <= cutoff], bins=bins, color="darkorange", alpha=0.6, label="Predicted", edgecolor="white")
    ax.set_xlabel("TPM")
    ax.set_ylabel("Count")
    ax.set_title(f"True vs Predicted TPM Distribution — {task_name}")
    ax.legend()
    ax.text(0.98, 0.97,
            f"Outliers excluded (> {cutoff:.2f} TPM):\n"
            f"  True:      {n_true_out} ({100 * n_true_out / len(true_vals):.1f}%)\n"
            f"  Predicted: {n_pred_out} ({100 * n_pred_out / len(pred_vals):.1f}%)",
            transform=ax.transAxes, fontsize=8, va="top", ha="right",
            bbox=dict(boxstyle="round,pad=0.3", facecolor="lightyellow", edgecolor="gray", alpha=0.8))
    plt.tight_layout()
    plt.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Saved combined histogram to: {out_path}")
    plt.close(fig)


def run_inference(model, tokenizer, test_data, args, device):
    test_data.set_format(type="torch", columns=["input_ids", "attention_mask", "labels"])
    collator = DataCollatorWithPadding(tokenizer=tokenizer)
    loader = DataLoader(test_data, batch_size=args.batch_size, collate_fn=collator)

    all_preds = []
    all_labels = []

    with torch.no_grad():
        for batch in loader:
            input_ids      = batch["input_ids"].to(device)
            attention_mask = batch["attention_mask"].to(device)
            labels         = batch["labels"]

            outputs = model(input_ids=input_ids, attention_mask=attention_mask)
            logits  = outputs.logits.cpu()

            all_preds.append(logits)
            all_labels.append(labels)

    all_preds  = torch.cat(all_preds,  dim=0).float().numpy()
    all_labels = torch.cat(all_labels, dim=0).float().numpy()

    # Squeeze single-output regression dim
    if all_preds.ndim == 2 and all_preds.shape[-1] == 1:
        all_preds  = all_preds.squeeze(-1)
        all_labels = all_labels.squeeze(-1)

    return all_preds, all_labels


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--task_name", type=str, required=True, choices=TASK_NAMES)
    parser.add_argument("--dataset", type=str, default="pgb", choices=DATASET_NAMES.keys())
    parser.add_argument("--tissue_idx", type=int, default=None,
                        help="Single tissue index. If omitted, all tissues are averaged.")
    parser.add_argument("--n_samples", type=int, default=None,
                        help="Number of test examples to sample. If omitted, uses the full test set.")
    parser.add_argument("--batch_size", type=int, default=4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out_dir", type=str, default="prediction_accuracy",
                        help="Directory to save plots and summary stats. Defaults to a 'prediction_accuracy' subfolder in the script's directory.")
    args = parser.parse_args()

    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # --- Output directory ---
    out_dir = os.path.join(os.path.dirname(__file__), "prediction_accuracy", args.task_name)
    os.makedirs(out_dir, exist_ok=True)

    # --- Load model ---
    print(f"Loading model from: {args.checkpoint}")
    model, tokenizer = load_model_and_tokenizer(args.checkpoint)
    model.to(device)

    # --- Load test data ---
    data_path = DATASET_NAMES[args.dataset]
    print(f"Loading test data for task: {args.task_name}")
    test_data = load_data(data_path, task_name=args.task_name, split="test",
                          tokenizer=tokenizer, tissue=args.tissue_idx)

    # --- Sample (optional) ---
    total = len(test_data)
    if args.n_samples is not None and args.n_samples < total:
        indices = np.random.choice(total, size=args.n_samples, replace=False)
        test_data = test_data.select(indices)
        print(f"Sampled {args.n_samples} / {total} test examples")
    else:
        print(f"Using full test set: {total} examples")

    # --- Inference ---
    all_preds, all_labels = run_inference(model, tokenizer, test_data, args, device)

    # If multi-tissue and no tissue_idx specified, flatten so each (gene, tissue)
    # pair is treated as an independent example in the plots.
    if all_labels.ndim == 2:
        n_tissues = all_labels.shape[1]
        print(f"Multi-tissue output ({n_tissues} tissues) — flattening to {all_labels.size} (gene, tissue) examples")
        all_preds  = all_preds.flatten()
        all_labels = all_labels.flatten()

    all_preds = np.maximum(all_preds, 0)

    print(f"True TPM  — min={all_labels.min():.3f}, max={all_labels.max():.3f}, mean={all_labels.mean():.3f}")
    print(f"Pred TPM  — min={all_preds.min():.3f},  max={all_preds.max():.3f},  mean={all_preds.mean():.3f}")

    # --- Summary stats ---
    save_summary_stats(
        all_labels, all_preds, args.task_name,
        os.path.join(out_dir, "summary_stats.json")
    )

    # --- Plots ---
    plot_boxplot(
        all_labels, all_preds, args.task_name,
        os.path.join(out_dir, "boxplot.png")
    )
    plot_histogram(
        all_labels, "True", args.task_name,
        os.path.join(out_dir, "histogram_true.png"),
        color="steelblue"
    )
    plot_histogram(
        all_preds, "Predicted", args.task_name,
        os.path.join(out_dir, "histogram_predicted.png"),
        color="darkorange"
    )
    plot_combined_histogram(
        all_labels, all_preds, args.task_name,
        os.path.join(out_dir, "histogram_combined.png")
    )


if __name__ == "__main__":
    main()
