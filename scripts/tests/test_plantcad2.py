#!/usr/bin/env python3
import torch
from transformers import AutoTokenizer, AutoModelForMaskedLM

WEIGHTS_DIR = "/nfs/stak/users/lowecal/evo2_shared/calebstuff/plantbench/weights/PlantCAD2/Small"
SEQUENCE = "ATCGATCGATCGATCGATCGATCG"

device = "cuda:0" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device}")

print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(
    WEIGHTS_DIR, local_files_only=True, trust_remote_code=True,
)

print("Loading model...")
model = AutoModelForMaskedLM.from_pretrained(
    WEIGHTS_DIR, local_files_only=True, trust_remote_code=True,
).to(device)
model.eval()

input_ids = tokenizer.encode_plus(
    SEQUENCE,
    return_tensors="pt",
    return_attention_mask=False,
    return_token_type_ids=False,
)["input_ids"].to(device)

with torch.inference_mode():
    outputs = model(input_ids=input_ids, output_hidden_states=True)

raw = outputs.hidden_states[-1].to(torch.float32)
hidden_size = raw.shape[-1] // 2
forward = raw[..., :hidden_size]
reverse = torch.flip(raw[..., hidden_size:], dims=[1])
embedding = (forward + reverse) / 2

print(f"Embedding shape: {embedding.shape}")
print("OK")




# #!/usr/bin/env python3
# import sys
# import os
# import torch

# # Patch 1: fix triton's libcuda_dirs() Python-level assertion
# import triton.backends.nvidia.driver as _triton_nvdrv
# _orig_libcuda_dirs = _triton_nvdrv.libcuda_dirs
# def _patched_libcuda_dirs():
#     try:
#         dirs = _orig_libcuda_dirs()
#     except Exception:
#         dirs = []
#     dirs.append('/usr/local/cuda/compat/lib')
#     return dirs
# _triton_nvdrv.libcuda_dirs = _patched_libcuda_dirs

# # Patch 2: fix triton's gcc invocation to include paths where --nv
# # actually put libcuda.so.1. Triton hardcodes -L flags that miss the
# # Apptainer-injected driver path, so we add LD_LIBRARY_PATH dirs and
# # common fallbacks directly into the gcc command.
# import triton.runtime.build as _triton_build
# _orig_build = _triton_build._build
# def _patched_build(name, src, tmpdir, library_dirs, include_dirs, libraries, ccflags=None):
#     ld_paths = os.environ.get('LD_LIBRARY_PATH', '').split(':')
#     extra = [p for p in ld_paths if p and os.path.exists(p)]
#     extra += ['/usr/lib/x86_64-linux-gnu', '/usr/lib64', '/usr/lib']
#     library_dirs = list(library_dirs) + extra
#     return _orig_build(name, src, tmpdir, library_dirs, include_dirs, libraries, ccflags)
# _triton_build._build = _patched_build

# from transformers import AutoTokenizer, AutoModelForMaskedLM

# WEIGHTS_DIR = "/nfs/stak/users/lowecal/evo2_shared/calebstuff/plantbench/weights/PlantCAD2/Small"
# SEQUENCE = "ATCGATCGATCGATCGATCGATCG"

# device = "cuda:0" if torch.cuda.is_available() else "cpu"
# print(f"Using device: {device}")

# print("Loading tokenizer...")
# tokenizer = AutoTokenizer.from_pretrained(
#     WEIGHTS_DIR, local_files_only=True, trust_remote_code=True,
# )

# print("Loading model...")
# model = AutoModelForMaskedLM.from_pretrained(
#     WEIGHTS_DIR, local_files_only=True, trust_remote_code=True,
# ).to(device)
# model.eval()

# input_ids = tokenizer.encode_plus(
#     SEQUENCE,
#     return_tensors="pt",
#     return_attention_mask=False,
#     return_token_type_ids=False,
# )["input_ids"].to(device)

# with torch.inference_mode():
#     outputs = model(input_ids=input_ids, output_hidden_states=True)

# raw = outputs.hidden_states[-1].to(torch.float32)
# hidden_size = raw.shape[-1] // 2
# forward = raw[..., :hidden_size]
# reverse = torch.flip(raw[..., hidden_size:], dims=[1])
# embedding = (forward + reverse) / 2

# print(f"Embedding shape: {embedding.shape}")
# print("OK")