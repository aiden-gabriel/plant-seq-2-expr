# solanum_lycopersicum_nt Performance

## All statistics calculated on solanum_lycopersicum test set of: https://huggingface.co/datasets/aiden-n-gabriel/pgb_exp_parquet

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

## R² Performance

**Average R²:** 0.513

### Per-Tissue R²
| # | Tissue | R² |
|--:|--------|---:|
| 0 | 1cm_fruit | 0.539 |
| 1 | 2cm_fruit | 0.540 |
| 2 | 3cm_fruit | 0.525 |
| 3 | breaker_fruit | 0.492 |
| 4 | flower | 0.499 |
| 5 | flower_bud | 0.502 |
| 6 | fruit_10d | 0.487 |
| 7 | leaf | 0.500 |
| 8 | mature_green_fruit | 0.509 |
| 9 | root | 0.515 |

### Plots

![R² per tissue bar chart — tissues ranked by index along the x-axis, R² on the y-axis. Highlights the low outlier at index 18 (mature_leaf_tissue_leaf_8).](r2_per_tissue.png)

![R² distribution histogram — distribution of R² scores across all 23 tissues.](r2_distribution.png)

