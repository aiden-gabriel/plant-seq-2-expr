#!/usr/bin/env python3
import sys
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

WEIGHTS_DIR = "/nfs/stak/users/lowecal/evo2_shared/calebstuff/plantbench/weights/GENERator/Small_1.2b"
sys.path.insert(0, WEIGHTS_DIR)

SEQUENCE = ["ATCGATCGATCGATCGATCGATCG"]  # 24 bp — already a multiple of 6

print("Loading model...")
tokenizer = AutoTokenizer.from_pretrained(WEIGHTS_DIR, local_files_only=True, trust_remote_code=True)
model = AutoModelForCausalLM.from_pretrained(WEIGHTS_DIR, local_files_only=True)
model.eval()

max_length = model.config.max_position_embeddings

# GENERator requires sequences trimmed to a multiple of 6 bp, prefixed with BOS token
processed = [tokenizer.bos_token + seq[:len(seq) // 6 * 6] for seq in SEQUENCE]

tokenizer.padding_side = "right"
tokens = tokenizer(
    processed,
    add_special_tokens=True,
    return_tensors="pt",
    padding=True,
    truncation=True,
    max_length=max_length,
)

with torch.inference_mode():
    out = model(**tokens, output_hidden_states=True)

embedding = out.hidden_states[-1]
print(f"Embedding shape: {embedding.shape}")
print("OK")