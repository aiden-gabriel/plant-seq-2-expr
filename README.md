## Setup
**If you don't want to use wandb you can comment it out in environment.yaml*

#### Using Conda 
**setup.sh will create a conda environment, if you want to use another type of environment use the environment.yaml file* 
    cd setup
    chmod +x setup.sh
    ./setup.sh

The standard environment name defined in environment.yaml is: "nt"

### Testing Setup
Run each of the test scripts in /tests to ensure models and data can be loaded

## Pretrained Models
aiden-n-gabriel/arabidopsis_thaliana_nt
aiden-n-gabriel/glycine_max_nt
aiden-n-gabriel/oryza_sativa_nt
aiden-n-gabriel/solanum_lycopersicum_nt
aiden-n-gabriel/zea_mays_nt

*See model performance metrics in /docs/pretrained_models/*

## Dataset
aiden-n-gabriel/pgb_exp_parquet

## Training
- Models can be trained using the train.sh which will use train.py as the main python file.
- Arguments for train.py are detailed in /docs/training/train_args.md


### Standard Model Saving Format
|-- runs
|   |-- {species}_{run_time}
|       |-- results.csv             # Contains r^2 score per tissue and avg
|       |-- checkpoint              # Saved model
|           |-- training_metadata   # Training parameters
|           |-- ... all other model saving files ...