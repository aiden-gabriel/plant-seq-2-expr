import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import torch
import pytest
from utils.load_pretrained_model import load_model_and_tokenizer, _is_hub_model

HF_REPO = "aiden-n-gabriel/arabidopsis_thaliana_nt"
EXPECTED_NUM_LABELS = 56
# Short but valid DNA sequence for a forward-pass smoke test
TEST_SEQUENCE = "ATCGATCGATCGATCGATCGATCGATCGATCG"


@pytest.fixture(scope="module")
def model_and_tokenizer():
    return load_model_and_tokenizer(HF_REPO)


def test_is_hub_model_detection():
    assert _is_hub_model("aiden-n-gabriel/arabidopsis_thaliana_nt") is True
    assert _is_hub_model("/nfs/some/local/checkpoint") is False
    assert _is_hub_model("./relative/path") is False


def test_load_from_huggingface(model_and_tokenizer):
    model, tokenizer = model_and_tokenizer
    assert model is not None
    assert tokenizer is not None


def test_model_in_eval_mode(model_and_tokenizer):
    model, _ = model_and_tokenizer
    assert not model.training


def test_forward_pass_output_shape(model_and_tokenizer):
    model, tokenizer = model_and_tokenizer
    inputs = tokenizer(TEST_SEQUENCE, return_tensors="pt")
    with torch.no_grad():
        outputs = model(**inputs)
    assert outputs.logits.shape == (1, EXPECTED_NUM_LABELS), (
        f"Expected logits shape (1, {EXPECTED_NUM_LABELS}), got {outputs.logits.shape}"
    )


def test_forward_pass_output_is_finite(model_and_tokenizer):
    model, tokenizer = model_and_tokenizer
    inputs = tokenizer(TEST_SEQUENCE, return_tensors="pt")
    with torch.no_grad():
        outputs = model(**inputs)
    assert torch.isfinite(outputs.logits).all(), "Model output contains NaN or Inf"


if __name__ == "__main__":
    print(f"Loading model from HuggingFace: {HF_REPO}")
    m, tok = load_model_and_tokenizer(HF_REPO)
    print("  load_model_and_tokenizer: OK")
    print(f"  eval mode: {not m.training}")

    inputs = tok(TEST_SEQUENCE, return_tensors="pt")
    with torch.no_grad():
        out = m(**inputs)
    print(f"  forward pass logits shape: {out.logits.shape}")
    assert out.logits.shape == (1, EXPECTED_NUM_LABELS)
    assert torch.isfinite(out.logits).all()
    print("All tests passed.")
