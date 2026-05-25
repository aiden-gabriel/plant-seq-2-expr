# zea_mays_nt

## All statistics calculated on zea_mays test set of: https://huggingface.co/datasets/aiden-n-gabriel/pgb_exp_parquet

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

**Average R²:** 0.637

### Per-Tissue Performance

| # | Tissue | R² |
|--:|--------|---:|
| 0 | Internode_6.7 | 0.661 |
| 1 | Internode_7.8 | 0.629 |
| 2 | Mature_pollen | 0.594 |
| 3 | Primary_root | 0.683 |
| 4 | Root_cortex | 0.661 |
| 5 | Root_elongation_zone | 0.601 |
| 6 | Root_maturation_zone | 0.612 |
| 7 | Secondary_root | 0.663 |
| 8 | Vegetative_Meristem_Surrounding_Tissue | 0.656 |
| 9 | X2.4_mm_from_tip_of_ear_primordium | 0.647 |
| 10 | X6.8_mm_from_tip_of_ear_primordium | 0.657 |
| 11 | embryos | 0.638 |
| 12 | embryos_20_days_after_pollination | 0.630 |
| 13 | endosperm_12_days_after_pollination | 0.584 |
| 14 | endosperm_crown | 0.668 |
| 15 | germinating_kernels | 0.671 |
| 16 | growth_zone | 0.638 |
| 17 | mature_female_spikelets | 0.642 |
| 18 | mature_leaf_tissue_leaf_8 | 0.480 |
| 19 | pericarp_and_aleurone | 0.623 |
| 20 | silks | 0.676 |
| 21 | stomatal_division_zone | 0.683 |
| 22 | symmetrical_division_zone | 0.691 |

### Plots

![R² per tissue bar chart — tissues ranked by index along the x-axis, R² on the y-axis. Highlights the low outlier at index 18 (mature_leaf_tissue_leaf_8).](r2_per_tissue.png)

![R² distribution histogram — distribution of R² scores across all 23 tissues.](r2_distribution.png)
