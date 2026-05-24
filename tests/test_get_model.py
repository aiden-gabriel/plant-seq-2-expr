import sys
sys.path.insert(0, ".")

from ../utils.get_model_for_training import get_model

MODEL_NAME = "InstaDeepAI/agro-nucleotide-transformer-1b"
NUM_LABELS = 5
LORA_R = 8
LORA_ALPHA = 16
LORA_DROPOUT = 0.1
LORA_TARGET_MODULES = ["query", "value"]

model = get_model(
    model_name=MODEL_NAME,
    num_labels=NUM_LABELS,
    fine_tune_method="lora",
    lora_r=LORA_R,
    lora_alpha=LORA_ALPHA,
    lora_dropout=LORA_DROPOUT,
    lora_target_modules=LORA_TARGET_MODULES,
)

print(model)
