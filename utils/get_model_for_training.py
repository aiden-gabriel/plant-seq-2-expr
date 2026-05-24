from transformers import AutoModelForSequenceClassification
from peft import LoraConfig, TaskType, get_peft_model


def get_agro_nt(model_name, num_labels, fine_tune_method, lora_r, lora_alpha, lora_dropout, lora_target_modules):
    if fine_tune_method == "lora":
        model = AutoModelForSequenceClassification.from_pretrained(model_name, num_labels=num_labels, problem_type="regression", ignore_mismatched_sizes=True)
        lora_config = LoraConfig(
            task_type=TaskType.SEQ_CLS, inference_mode=False, r=lora_r, lora_alpha=lora_alpha, lora_dropout=lora_dropout, target_modules=lora_target_modules, #could add "intermediate.dense" and "output.dense" for MLP layers 
        )
        lora_classifier = get_peft_model(model, lora_config) # transform our classifier into a lora model
        lora_classifier.print_trainable_parameters()
        return lora_classifier
    else:
        raise ValueError(f"Unsupported fine-tuning method: {fine_tune_method}")

def get_model(model_name, num_labels, fine_tune_method, lora_r, lora_alpha, lora_dropout, lora_target_modules):
    if model_name == "InstaDeepAI/agro-nucleotide-transformer-1b":
        return get_agro_nt(model_name, num_labels, fine_tune_method, lora_r, lora_alpha, lora_dropout, lora_target_modules)
    elif "evo2" in model_name:
        return get_evo2(model_name, num_labels, fine_tune_method)
    else:
        raise ValueError(f"Unsupported model name: {model_name}")

