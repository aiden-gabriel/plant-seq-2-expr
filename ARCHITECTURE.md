seq-2-expr/
|-- eval/                           # contains eval scripts
|
|-- setup/                          # contains setup scripts and tests
|   |-- environment.yaml            # specifies dependencies and environment name
|   |-- setup.sh                    # script to run to set up environment
|
|-- utils/                          # helper python files
|   |-- dataloader.py               # loads data (right now just from Plant Genomic Benchmark)
|   |-- get_model_for_training.py   # loads a model and selects the frozen and tunable parameters
|   |-- load_pretrained_model.py    # loads a pretrained model for evaluation
|
|-- tests/                          # contains model and data loading tests to confirm envirnoment setup and access to resources

