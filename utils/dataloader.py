import pandas as pd
from datasets import Dataset, load_dataset


def tokenize_function(batch, tokenizer):
    return tokenizer(batch["sequence"], padding=False, truncation=True)


def _is_hub_dataset(data_path: str) -> bool:
    """Return True if data_path is a HuggingFace dataset repo ID."""
    return not data_path.startswith(("/", ".", "~")) and "/" in data_path


def load_data(data_path, task_name, split, tokenizer, tissue=None):
    if _is_hub_dataset(data_path):
        dataset = load_dataset(
            data_path,
            data_files={split: f"{task_name}/{split}.parquet"},
            split=split,
        )
    else:
        df = pd.read_parquet(f"{data_path}/{task_name}/{split}.parquet")
        dataset = Dataset.from_dict({
            "sequence": df["sequence"].tolist(),
            "labels": df["labels"].tolist(),
        })

    if tissue is not None:
        if tissue < 0 or tissue >= len(dataset["labels"][0]):
            raise ValueError(
                f"Invalid tissue index: {tissue}. "
                f"Must be between 0 and {len(dataset['labels'][0]) - 1}."
            )
        dataset = dataset.map(lambda ex: {"labels": [ex["labels"][tissue]]})

    print(f"dataloader: num_labels: {len(dataset['labels'][0])}")

    dataset = dataset.map(lambda batch: tokenize_function(batch, tokenizer), batched=True)

    # Needs an option to call for masks for gene overlap

    dataset.set_format(type="torch", columns=["input_ids", "attention_mask", "labels"])
    return dataset
