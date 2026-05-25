"""
test_evo2.py — BioNeMo Evo2 inference via Python API

Before running this script, you must first convert the checkpoint:
    apptainer exec --nv ~/hpc-share/apptainer/bionemo-evo2.sif \
        evo2_convert_to_nemo2 \
            --model-path "hf://arcinstitute/savanna_evo2_7b_base" \
            --model-size 7b \
            --output-dir ~/hpc-share/weights/bionemo-evo2/nemo2_evo2_7b_8k

Then run this script:
    apptainer exec --nv ~/hpc-share/apptainer/bionemo-evo2.sif \
        python test_evo2.py
"""

from pathlib import Path
from bionemo.evo2.run.infer import infer

CHECKPOINT_DIR = str(Path.home() / "hpc-share/weights/bionemo-evo2/nemo2_evo2_7b_8k")
SEQUENCE = "ATGCGTACGATCGATCGATCGATCG"

if not Path(CHECKPOINT_DIR).exists():
    raise FileNotFoundError(
        f"Checkpoint not found at {CHECKPOINT_DIR}. "
        "Run evo2_convert_to_nemo2 first — see the docstring above."
    )

print(f">>> Running inference on: {SEQUENCE}")

results = infer(
    prompt=SEQUENCE,
    ckpt_dir=CHECKPOINT_DIR,
    max_new_tokens=50,
    temperature=1.0,
    top_k=4,
    top_p=0.0,
    tensor_parallel_size=1,
    pipeline_model_parallel_size=1,
    context_parallel_size=1,
)

print(f">>> Generated: {results}")
print(">>> Test passed!")