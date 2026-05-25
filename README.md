# plant-seq-2-expr


## Setup

Using Conda (recommended) — `setup.sh` will create the environment automatically:

```bash
cd setup
chmod +x setup.sh
./setup.sh
```

To use a different environment manager, use `setup/environment.yaml` directly. The default environment name is `nt`.

> **Note:** W&B is included in `environment.yaml` but is optional — comment it out if you don't need experiment tracking.

### Testing Setup

Run each script in `/tests` to verify models and data load correctly.

---

## Pretrained Models

#### Fine-tuned AgroNT Models
| Model | HuggingFace |
|-------|-------------|
| *Arabidopsis thaliana* | `aiden-n-gabriel/arabidopsis_thaliana_nt` |
| *Glycine max* | `aiden-n-gabriel/glycine_max_nt` |
| *Oryza sativa* | `aiden-n-gabriel/oryza_sativa_nt` |
| *Solanum lycopersicum* | `aiden-n-gabriel/solanum_lycopersicum_nt` |
| *Zea mays* | `aiden-n-gabriel/zea_mays_nt` |

Performance metrics for each model are in [`/docs/pretrained_models`](docs/).

> **Note:** The model can output predictions below zero. For all evaluations, predictions below zero are clipped to zero — this is the recommended inference behavior.

---

## Dataset

`aiden-n-gabriel/pgb_exp_parquet` on HuggingFace.

---

## Training

Models are trained via `train.sh`, which calls `train.py`. See [`/docs/training/train_args.md`](docs/training/train_args.md) for all arguments.

### Output Format

```
runs/
└── {species}_{run_time}/
    ├── results.csv          # R² score per tissue and average
    └── checkpoint-####/     # Best performing model checkpoint
        ├── training_metadata
        └── ...              # All other model files
```
