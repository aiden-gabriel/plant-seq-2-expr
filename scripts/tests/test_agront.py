#!/usr/bin/env python3
import sys
import torch
from transformers import AutoModelForMaskedLM, AutoTokenizer

WEIGHTS_DIR = "/nfs/stak/users/lowecal/evo2_shared/calebstuff/plantbench/weights/AgroNT/1b"
sys.path.insert(0, WEIGHTS_DIR)

SEQUENCE = ["ATCGATCGATCGATCGATCGATCG"]

print("Loading model...")
tokenizer = AutoTokenizer.from_pretrained(WEIGHTS_DIR, local_files_only=True)
model = AutoModelForMaskedLM.from_pretrained(WEIGHTS_DIR, local_files_only=True, trust_remote_code=True)
model.eval()

tokens = tokenizer(SEQUENCE, return_tensors="pt")
with torch.no_grad():
    out = model(**tokens, output_hidden_states=True)

embedding = out.hidden_states[-1]
print(f"Embedding shape: {embedding.shape}")
print("OK")