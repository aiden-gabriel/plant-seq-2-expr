# oryza_sativa_nt Performance

## All statistics calculated on oryza_sativa test set of: https://huggingface.co/datasets/aiden-n-gabriel/pgb_exp_parquet

**Model can output predictions below zero, for all evaluation predictions below zero were set to zero as this is how we recommend the model to be used*

## Summary Statistics (averaged across all tissues)
| mae | __ |
| rmse | __ |
| r2 | __ |
| pearson_r | |
| true_mean |  |
| true_std |  |
| pred_mean |  |
| pred_std |  |

## R²

**Average R²:** 0.513

### Per-Tissue R²
| # | Tissue | R² |
|--:|--------|---:|
| 0 | Antherwall | 0.461 |
| 1 | Collar | 0.532 |
| 2 | Ligule | 0.514 |
| 3 | MatureAnther | 0.506 |
| 4 | Pollen | 0.417 |
| 5 | Roothair | 0.444 |
| 6 | Sheath | 0.512 |

### Plots

![R² per tissue bar chart — tissues ranked by index along the x-axis, R² on the y-axis. Highlights the low outlier at index 18 (mature_leaf_tissue_leaf_8).](r2_per_tissue.png)

![R² distribution histogram — distribution of R² scores across all 23 tissues.](r2_distribution.png)