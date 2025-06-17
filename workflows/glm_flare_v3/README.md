---
output: html_document
---

# ALEX-forecast-code

This workflow is the current automation of glm_flare_v3 for Lake Alexandrina and uses the configuration of the same name.

## Specific workflow implementations using glm_flare_v3

The implementation of the glm_flare_v3 for Lake Alexandrina has some differences compared to the usual set up (e.g. for FCR) that are detailed below. These relate to the methods to generate inflow forecasts, the assimilation of target observations in FLARE, the way the water balance is calculated in GLM using a weir crest, and the automated generation of management scenarios.

The `sim_name` for these automated forecasts is **`glm_flare_v3_crest`**.

### Assimilation of depth, salinity, and water temperature observation

As part of the Lake Alexandrina workflow we assimilate observations of lake water temperature and lake salinity (both from the surface, 0.5 m) and lake depth/height/level. These are specified in the [observations_config](../../configuration/glm_flare_v3/observations_config.csv).The assimilation of these data (especially lake depth) is crucial for the fitting of the `crest_elev` parameter during DA. As we do not specify an outlet for this configuration we use overflow over the crest as the estimate of outflow through barrages. See below.

### Using the weir crest as an outflow

We have configured GLM to have a weir as the primary means of outflow instead of a specified outflow. The dimensions of the weir crest are defined in the glm.nml (crest_elev in &morphometry, crest_width and crest_factor in &outflow). As assimilation of lake depth data occurs the crest_elev is lowered/raised corresponding to greater/reduced overflow possible (and changes in barrage flow). The crest_elev parameter is tuned during DA but then fixed during the forecast period. To do this we need to run the spin-up/look-back using a different par_fit_method (`config_flare_yaml$da_setup$par_fit_method`) than during the forecast period. Therefore, the workflow does the following:

-   for the DA period the run_config is updated to: set the forecast_horizon = 0 and in the flare_config the `da_setup$par_fit_method` is set to `peturb`.
-   runs the spin-up/look-back up to today, stops FLARE, reads in the 'forecast' output and copies restart.nc files to prevent overwriting (and to use later for the scenarios! - see below).
-   for the forecast period the run_config is updated to: set the forecast_horizon back to the original value, set the forecast_start_datetime and the start_datetime to the date of forecast generation ('today' with no spin-up) and specify to use the restart.nc that we just copied. The flare_config is edited to set `da_setup$par_fit_method` = `perturb_init` which retains the distribution of the parameter values to those from the end of DA (all parameters not just crest_elev - no increase in parameter uncertainty with horizon).
-   run FLARE for the forecast period and read in the 'forecast' output and combine with those from the DA period and then write this out to the correct parquet location.

This is the 'reference' scenario that assumes no change in crest_elev during the forecast period (the `sim_name` is `glm_flare_v3_crest` to show that we are using the crest_elev configuration and not an outlet).

### Alternate barrage scenarios

Once the reference forecast is finished the workflow then generates two alternate scenarios that decrease and increase the crest_elev parameter (representing lowering and raising of the barrages = more or less overflow). This happens using a for loop for each scenario:

```{r}
scenario_sim_names <- 
  expand.grid(dir = c('up', 'down'), crest_elev_change = c(0.1)) |> 
  mutate(sim_name = paste0("glm_flare_v3_crest_", dir, "_", crest_elev_change))

```

For each scenario, the forecast starts from the end of the DA period (step 2 above) using this restart file. So the steps are as follows

1.  edit the restart file with the new `sim_name` and copy the restart file from the reference scenario into a new restart directory for this scenario
2.  edit the `run_config` with the scenario `sim_name` (prevent overwriting the reference forecast we just made). The `sim_name` also controls the restart file that is used/made during the running of FLARE
3.  sets the horizon, start_datetime, forecast_start_datetime in this new config
4.  **Opens the restart.nc file and changes the parameter values (these the scenarios being implemented)!**
5.  Run FLARE for the scenario forecast period!
6.  Read in the forecast output and combine with the DA period we read in earlier --\> save this using the scenario sim_name.

The final step is to make sure that the *actual* restart file run_config is correct for tomorrow - so we set the start_datetime and forecast_start_datetime, horizon to the correct values e.g. sim_name reset to `glm_flare_v3`, move `forecast_start_datetime` ahead a day, look back x number of days and set horizon back to 35 days.

### Inflow forecast generation

The inflow forecasts used in these lake water quality forecasts use a range of "helper data" (see `R/helper_data`) that were provided by South Australia's Department for Environment & Water (DEW) for use in the inflow discharge forecast generation. See the [README](../../R/helper_data/README.md) for more information about these data. The goal of these forecasts was to make predictions with uncertainty of inflow discharge for Lake Alexandrina at Wellington (where there are no observations of flow) using upstream observations (from the calculated flow at SA border of which there are real-time observations), a travel or lag time, and a loss function (how much water is lost from the river between these two locations).

The summary of how the inflow discharge forecasts are generated is as follows (using the functions in [`R/inflow_flow_process.R`](../../R/inflow_flow_process.R) and implemented in [`baseline_inflow_workflow.R`](baseline_inflow_workflow.R):

1.  Fit the loss model - using the [modelled_losses](../../R/helper_data/modelled_losses.csv) data fit a model between the discharge at SA border and the loss to Wellington (as modelled by DEW's Source model), that can then be used to derive the forecasted loss. Uses the `model_losses` function that returns a fitted model.

2.  Fit the travel time model - using the [travel_times](../../R/helper_data/travel_times.csv) data fit a model between the discharge at SA border and the travel time to Wellington (as modelled by DEW's Source model), that can then be used to derive the forecasted travel time. Uses the `model_traveltime` function that returns a fitted model.

> Both of the functions that are used to estimate these models also take an argument `obs_unc`, which can be used to add uncertainty to the 'observations' which are used to fit the model and then include the process uncertainty into the predictions of loss and travel times. The value given should be a percentage of the mean value (e.g. 0.05 would apply a 5% error on the mean loss/travel time).

Travel times from SA border to Wellington are between 5 and 20 days which means you can use the observations up to 5-20 days into the future. Beyond this horizon we don't know what the 'observation' of flow upstream will be to predict downstream. So, we extend the SA border 'observations' using a RW model (assuming persistence with some error) to make predictions of SA border discharge to the end of the forecast horizon that can then be passed into the loss and travel time models. Because we know there are some limits on what the flow is likely to be at the SA border we bound the RW using an upper and lower limits defined by entitlement flow (lower limit) and an average environmental flow + entitlement (upper limit) as defined in the helper_data for [entitlement_flow.csv](../../R/helper_data/entitlement_flow.csv) and [eflow.csv](../../R/helper_data/eflow.csv), which both vary by month. This happens inside the `generate_flow_inflow_fc` function.

3.  Generate the inflow flow forecast at Wellington using the two fitted models and the total time series of flow at SA border to estimate the flow at Wellington. You can specify whether to include the uncertainty from the two models (`tt_unc` and `loss_unc = TRUE/FALSE`). All of this get's done in ML/day which then get's converted into m3/s for FLARE.

The inflow temperature and salinity forecasts are generated using XGBoost models [`R/inflow_salt_xgboost.R`](../../R/inflow_salt_xgboost.R) and [`R/inflow_temperature_xgboost.R`](../../R/inflow_temperature_xgboost.R) in the [`baseline_inflow_workflow.R`](baseline_inflow_workflow.R) and use meteorological forecasts and historical observations of inflow temperature and salinity from the Wellington location.

#### Historical inflows

For any historical/spin/look-back period the same method is applied to observations of discharge at the SA border (losses + travel time) using the `predict_downstream` function (which is technically inside the `generate_flow_inflow_fc` but is not called directly unlike for the historical period). These are combined with observations of salt and temperature at Wellington (available realtime and generated in [targets](generate_targets.R) and interpolated).

### 

------------------------------------------------------------------------

## More information

These workflows and configurations were initially developed as part of the Global Centers design grant (NSF OISE-2330211). For the specific details on the manuscript Olsson et al. titled "Developing scenario-based, near-term iterative forecasts to inform water management" visit <https://github.com/OlssonF/ALEX-forecast-code> or contact Freya Olsson at [freyao\@vt.edu](mailto:freyao@vt.edu){.email}.
