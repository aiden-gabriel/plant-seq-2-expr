import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import torch
import pytest
from transformers import AutoTokenizer
from utils.dataloader import load_data, _is_hub_dataset

HF_DATASET = "aiden-n-gabriel/pgb_exp_parquet"
TOKENIZER_NAME = "InstaDeepAI/agro-nucleotide-transformer-1b"
TASK_NAME = "arabidopsis_thaliana"
EXPECTED_NUM_LABELS = 56


@pytest.fixture(scope="module")
def tokenizer():
    return AutoTokenizer.from_pretrained(TOKENIZER_NAME)


@pytest.fixture(scope="module")
def test_dataset(tokenizer):
    return load_data(HF_DATASET, task_name=TASK_NAME, split="test", tokenizer=tokenizer)


# --- Path detection ---

def test_is_hub_dataset_hf_repo():
    assert _is_hub_dataset("aiden-n-gabriel/pgb_exp_parquet") is True

def test_is_hub_dataset_absolute_path():
    assert _is_hub_dataset("/nfs/some/local/path") is False

def test_is_hub_dataset_relative_path():
    assert _is_hub_dataset("./relative/path") is False

def test_is_hub_dataset_home_path():
    assert _is_hub_dataset("~/datasets/pgb") is False


# --- Columns and tensor types ---

def test_dataset_returns_required_keys(test_dataset):
    sample = test_dataset[0]
    assert "input_ids" in sample
    assert "attention_mask" in sample
    assert "labels" in sample

def test_dataset_returns_torch_tensors(test_dataset):
    sample = test_dataset[0]
    assert isinstance(sample["input_ids"], torch.Tensor)
    assert isinstance(sample["attention_mask"], torch.Tensor)
    assert isinstance(sample["labels"], torch.Tensor)


# --- Label shape ---

def test_labels_have_correct_num_tissues(test_dataset):
    sample = test_dataset[0]
    assert sample["labels"].shape == torch.Size([EXPECTED_NUM_LABELS])

def test_labels_are_finite(test_dataset):
    sample = test_dataset[0]
    assert torch.isfinite(sample["labels"]).all()


# --- Tissue filtering ---

def test_tissue_filter_reduces_label_to_one(tokenizer):
    ds = load_data(HF_DATASET, task_name=TASK_NAME, split="test", tokenizer=tokenizer, tissue=0)
    assert ds[0]["labels"].shape == torch.Size([1])

def test_tissue_filter_last_index(tokenizer):
    ds = load_data(HF_DATASET, task_name=TASK_NAME, split="test", tokenizer=tokenizer, tissue=EXPECTED_NUM_LABELS - 1)
    assert ds[0]["labels"].shape == torch.Size([1])

def test_tissue_filter_invalid_index_raises(tokenizer):
    with pytest.raises(ValueError, match="Invalid tissue index"):
        load_data(HF_DATASET, task_name=TASK_NAME, split="test", tokenizer=tokenizer, tissue=EXPECTED_NUM_LABELS)


# --- Splits ---

def test_all_splits_are_nonempty(tokenizer):
    for split in ("train", "validation", "test"):
        ds = load_data(HF_DATASET, task_name=TASK_NAME, split=split, tokenizer=tokenizer)
        assert len(ds) > 0, f"Split '{split}' loaded empty"

def test_train_split_larger_than_test(tokenizer):
    train = load_data(HF_DATASET, task_name=TASK_NAME, split="train", tokenizer=tokenizer)
    test  = load_data(HF_DATASET, task_name=TASK_NAME, split="test",  tokenizer=tokenizer)
    assert len(train) > len(test)


# --- Multiple species ---

@pytest.mark.parametrize("task_name", [
    "glycine_max",
    "oryza_sativa",
    "solanum_lycopersicum",
    "zea_mays",
])
def test_other_species_load(tokenizer, task_name):
    ds = load_data(HF_DATASET, task_name=task_name, split="test", tokenizer=tokenizer)
    assert len(ds) > 0
    sample = ds[0]
    assert "input_ids" in sample
    assert "labels" in sample


if __name__ == "__main__":
    tok = AutoTokenizer.from_pretrained(TOKENIZER_NAME)
    print(f"Loading {TASK_NAME} test split from {HF_DATASET}...")
    ds = load_data(HF_DATASET, task_name=TASK_NAME, split="test", tokenizer=tok)
    s = ds[0]
    print(f"  input_ids shape:      {s['input_ids'].shape}")
    print(f"  attention_mask shape: {s['attention_mask'].shape}")
    print(f"  labels shape:         {s['labels'].shape}")
    assert s["labels"].shape == torch.Size([EXPECTED_NUM_LABELS])
    print("All checks passed.")
