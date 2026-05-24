Setup:
    cd setup
    chmod +x setup.sh
    ./setup.sh

Testing Setup
Run each of the test scripts in /tests to ensure models and data can be loaded

Model Saving
|-- runs
|   |-- {species}_{run_time}
|       |-- results.csv             # Contains r^2 score per tissue and avg
|       |-- checkpoint              # Saved model
|           |-- training_metadata   # Training parameters
|           |-- ... all other model saving files ...

Models
aiden-n-gabriel/arabidopsis_thaliana_nt
aiden-n-gabriel/glycine_max_nt
aiden-n-gabriel/oryza_sativa_nt
aiden-n-gabriel/solanum_lycopersicum_nt
aiden-n-gabriel/zea_mays_nt

Dataset
aiden-n-gabriel/pgb_exp_parquet