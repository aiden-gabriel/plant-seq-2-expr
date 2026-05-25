#!/usr/bin/env python3
import os
import sys
import torch
from pathlib import Path
from transformers import AutoTokenizer, AutoModel

WEIGHTS_DIR = Path("/nfs/stak/users/lowecal/evo2_shared/calebstuff/plantbench/weights/DNABERT-2/117M")
SEQUENCE    = "ACGTAGCATCGGATCTATCTATCGACACTTGGTTATCGATCTACGAGCATCTCGTTAGC"

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(WEIGHTS_DIR, local_files_only=True, trust_remote_code=True)
print("Loading model...")
model = AutoModel.from_pretrained(WEIGHTS_DIR, local_files_only=True, trust_remote_code=True)
print("Model loaded.")

# Disable flash_attn_triton — falls back to built-in PyTorch attention
for mod in sys.modules.values():
    if hasattr(mod, 'flash_attn_qkvpacked_func'):
        mod.flash_attn_qkvpacked_func = None

model.eval()
model = model.to(device)

inputs = tokenizer(SEQUENCE, return_tensors="pt")["input_ids"].to(device)
with torch.no_grad():
    hidden_states = model(inputs)[0]

embedding = torch.mean(hidden_states[0], dim=0)
print(f"Embedding shape: {embedding.shape}")
print("OK")