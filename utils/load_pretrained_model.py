import os
import json
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from peft import PeftModel
from safetensors import safe_open
from huggingface_hub import hf_hub_download

BASE_MODEL = "InstaDeepAI/agro-nucleotide-transformer-1b"


def _is_hub_model(path: str) -> bool:
    """Return True if path looks like a HuggingFace repo ID (e.g. 'user/repo-name')."""
    return not path.startswith(("/", ".", "~")) and path.count("/") == 1


def load_agro_nt_training_metadata(checkpoint_path: str) -> dict:
    """Load training_metadata.json from a local checkpoint dir or a HF repo."""
    if _is_hub_model(checkpoint_path):
        local_path = hf_hub_download(checkpoint_path, "training_metadata.json")
        with open(local_path) as f:
            return json.load(f)
    metadata_path = os.path.join(checkpoint_path, "training_metadata.json")
    if not os.path.exists(metadata_path):
        raise FileNotFoundError(
            f"No training_metadata.json found in {checkpoint_path}. "
            "This checkpoint was saved before metadata tracking was added."
        )
    with open(metadata_path) as f:
        return json.load(f)


def get_num_labels_from_checkpoint(checkpoint_path: str) -> int:
    """Infer num_labels from the saved classifier weight shape in the adapter checkpoint."""
    if _is_hub_model(checkpoint_path):
        safetensors_path = hf_hub_download(checkpoint_path, "adapter_model.safetensors")
    else:
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


def load_agro_nt_lora(model_path: str):
    """Load an AgroNT LoRA model from a local path or a HuggingFace repo ID."""
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    num_labels = get_num_labels_from_checkpoint(model_path)
    print(f"Inferred num_labels={num_labels} from checkpoint")
    base = AutoModelForSequenceClassification.from_pretrained(
        BASE_MODEL, num_labels=num_labels, ignore_mismatched_sizes=True
    )
    model = PeftModel.from_pretrained(base, model_path)
    model.eval()
    return model, tokenizer


def load_model_and_tokenizer(model_path, base_model="agro_nt", fine_tune_method="lora"):
    """Load a fine-tuned model and its tokenizer.

    model_path can be either a local checkpoint directory or a HuggingFace repo ID
    (e.g. 'aiden-n-gabriel/arabidopsis_thaliana_nt').
    """
    if base_model == "agro_nt":
        if fine_tune_method == "lora":
            return load_agro_nt_lora(model_path)
        else:
            raise ValueError(f"Unsupported fine-tuning method {fine_tune_method} for model {base_model}")
    else:
        raise ValueError(f"Unsupported model {base_model}")
