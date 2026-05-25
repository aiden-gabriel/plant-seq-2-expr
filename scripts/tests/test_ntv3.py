#!/usr/bin/env python3
import os
import sys
import torch

WEIGHTS_DIR = "/nfs/stak/users/lowecal/evo2_shared/calebstuff/plantbench/weights/NTv3/Large"

# Add weights dir to path so the local .py files are importable
sys.path.insert(0, WEIGHTS_DIR)

from tokenization_ntv3 import NTv3Tokenizer
from modeling_ntv3_pretrained import NTv3PreTrained
from configuration_ntv3_pretrained import Ntv3PreTrainedConfig

SEQUENCE = ["ATCGATCGATCGATCGATCGATCG"]

print("Loading model...")
tokenizer = NTv3Tokenizer.from_pretrained(WEIGHTS_DIR)
config    = Ntv3PreTrainedConfig.from_pretrained(WEIGHTS_DIR)
model     = NTv3PreTrained.from_pretrained(WEIGHTS_DIR, config=config)
model.eval()

tokens = tokenizer(SEQUENCE, add_special_tokens=False, padding=True, pad_to_multiple_of=128, return_tensors="pt")
with torch.no_grad():
    out = model(**tokens, output_hidden_states=True)

embedding = out.hidden_states[-1]
print(f"Embedding shape: {embedding.shape}")
print("OK")