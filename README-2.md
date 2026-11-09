# DMAPRIME-QEns: DoD Respiratory Forecasts

Weekly probabilistic forecasts of COVID-19, influenza and RSV activity for the **DoD AFHSD-IB Respiratory Forecasting Collaboration 2026–27**.

**Team:** DMAPRIME (CPHMR, Clemson University)
**Model:** DMAPRIME-QEns (pooled quantile ensemble)
**Contact:** Tanvir Ahammed <tahamme@g.clemson.edu>

`DoD_forecast_v1.2.r` is the weekly production script. One run reads the newest truth file, fits the models, forecasts 1–4 weeks ahead and writes the submission file in the challenge format.

---

## Targets

| Item | Value |
|---|---|
| Variables | `mhs_cov_percent`, `mhs_flu_percent`, `mhs_rsv_percent` (% of MHS outpatient encounters) |
| Horizons | 1, 2, 3 and 4 weeks ahead |
| Locations | Table 2 locations of the 2026–27 guidelines (regions and Defense Health Networks) |
| Output | 23 quantiles (0.01–0.99) and a point forecast with 95% limits |

---

## Method

**Transform.** Each series is modelled on the scale `z = y^(1/4)`, scaled and centred per location. The models predict the change in `z` over 1–4 weeks at 23 quantile levels.

**Inputs.** All inputs use only data up to the forecast week:
- the current level, local-polynomial trends over 3–6 weeks, rolling means and lags
- season week and weeks from Christmas
- location size and noise level
- the all-region trend and the parent-DHN trend
- the MHS case rate, the civilian percentage and wastewater, where available
- the NSSP civilian emergency-department visit percentage of the location's states

**Models.** Each model is trained on all locations together (pooled):

| Member | Model |
|---|---|
| `gbqr` | LightGBM quantile gradient boosting |
| `qrf` | quantile random forest |
| `xt` | extra-trees quantile forest |
| `lqr` | linear quantile regression |
| `knn` | nearest-neighbour analogs |
| `mlp` | neural network with residual quantiles |
| `ar`, `trend`, `seasonal`, `growthqr`, `gam`, `mars`, `ets`, `arima`, `theta` | additional candidates |

**Ensemble and calibration.** For each disease, the chosen members are combined (median or mean) and recalibrated, either with a spread factor or a PIT-based remapping of quantile levels. Optional steps are applied only when the backtest adopted them:
- calibration by location size
- an anti-lag correction
- a trend-aware calibration driven by a multi-signal "rising now" detector
- a hierarchy step linking locations to their DHN

**Recipe selection.** Which members, combination and calibration each disease uses is chosen out-of-sample by the rolling, leakage-checked backtest in `dod_resp_qr_v3.4.R`:
- seasons 2024–25 and 2025–26, leave-one-season-out
- scored by WIS, with rising, falling and flat weeks weighted equally
- a step is adopted only when the whole bootstrap 90% interval shows an improvement

The backtest writes its choices to `selection.csv`, which this script reads. Without a backtest result for a disease, `DEFAULT_SETTINGS` is used: the median of `gbqr + qrf + lqr` on DoD data.

**Current recipes (2024–26 backtest).** The table compares each recipe with the original setup (mean of `gbqr + qrf + lqr` with a spread factor):

| Disease | Data | Members | Combine | Calibration | vs. original setup |
|---|---|---|---|---|---|
| Influenza | DoD | gbqr + qrf + lqr | median | spread ×1.10 | 0.991 (0.987–0.995) |
| COVID-19 | DoD, from July 2022, no time-of-year inputs | gbqr + qrf + xt | median | size-aware PIT | 0.928 (0.908–0.950) |
| RSV | DoD | qrf + gbqr + xt | mean | spread ×1.05 | 0.981 (0.971–0.990) |

---

## Requirements

- R ≥ 4.3
- Packages: `data.table`, `ggplot2`, `lightgbm`, `ranger`, `quantreg`, `FNN`, `mgcv`, `earth`, `nnet`, `forecast`. Missing packages are installed automatically on the first run.
- Internet access for the automatic NSSP download (optional; the last saved copy is used offline).

---

## Data

The DoD surveillance data are **not included** in this repository. They are provided to participants under a data-sharing agreement.

| Input | Description |
|---|---|
| Truth file | `YYYY-EWnn-truth_regions_ext_DDMONYYYY.csv`, released weekly by AFHSD-IB; the newest file in `path_truth_dir` is used |
| `afhsd_region_dmisid_mapping.csv` | DMISID → DHN mapping (parent-DHN features) |
| `afhsd_region_county_mapping.csv` | region → counties and states (NSSP features) |
| NSSP | CDC open data, dataset `rdmq-nq56` (NSSP Emergency Department Visit Trajectories), downloaded automatically when `path_nssp <- "auto"` |
| `selection.csv`, `recal_map.csv`, `size_buckets.csv` | recipe settings written by `dod_resp_qr_v3.4.R` |

---

## Configuration

Settings are at the top of the script:

| Setting | Meaning |
|---|---|
| `BOX` | root folder containing the data and output folders |
| `path_truth_dir` | folder with the weekly truth files |
| `path_truth_file` | `NULL` for the newest file, or a specific file |
| `path_mapping`, `path_county` | mapping files |
| `path_nssp` | `"auto"` (download), a file path, or `NULL` (not used) |
| `nssp_dir` | where NSSP downloads are stored |
| `path_backtest` | folder with `selection.csv` from the backtest |
| `output_dir` | plots and working files |
| `submit_dir` | submission file and metadata |
| `DISEASES` | any of `"flu"`, `"cov"`, `"rsv"` |
| `FORECAST_REGIONS` | `"table2"`, `"all"`, or a vector of location names |
| `USE_BACKTEST_SETTINGS` | per disease: use `selection.csv` (`TRUE`) or `DEFAULT_SETTINGS` (`FALSE`) |
| `ONE_FILE` | `TRUE`: one combined file; `FALSE`: separate quantile and point files |
| `N_THREADS`, `SEED` | parallel threads and random seed |

`path_nssp` must match the setting used when the backtest was run.

---

## Usage

```r
source("DoD_forecast_v1.2.r")
```

or open the script in RStudio and click **Source**.

---

## Output

The submission file is written to `submit_dir`:

```
YYYY-MM-DD-DMAPRIME-QEns.csv
```

The date is the Monday forecast date. Columns:

```
region, epiweek, year, date, target, variable, model, quantile, value, llim, ulim
```

For each location, variable and target there is one `Point` row (median, with `llim` and `ulim` at the 2.5% and 97.5% quantiles), followed by the 23 quantile rows. Dates are `M/D/YYYY`, line endings are CRLF and values have 4 decimals. The file is checked against the challenge format before it is written.

`metadata-DMAPRIME-QEns.txt` is written to `submit_dir` on the first run. Forecast plots are written to `output_dir/plots`.

### Example

```
region,epiweek,year,date,target,variable,model,quantile,value,llim,ulim
Agana,41,2026,10/17/2026,1 wk ahead,mhs_cov_percent,DMAPRIME-QEns,Point,0.2678,0.1678,0.4845
Agana,41,2026,10/17/2026,1 wk ahead,mhs_cov_percent,DMAPRIME-QEns,0.01,0.1498,,
Agana,41,2026,10/17/2026,1 wk ahead,mhs_cov_percent,DMAPRIME-QEns,0.025,0.1678,,
```

---

## Repository

| File | Purpose |
|---|---|
| `DoD_forecast_v1.2.r` | weekly forecast and submission file |


---


