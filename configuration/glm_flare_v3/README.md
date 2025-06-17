# ALEX-forecast-code

This README includes details of the configuration set-up to run the glm_flare_v3 workflow using the custom workflows for Lake Alexandrina (crest elevation, scenarios etc.).

In here you can find information about some specific configuration settings that might be different to the regular FLARE set-up.

## configure_flare.yml

Configuration needed to output the overflow data (i.e. the calculated outflow over the crest) from the overflow.csv

---
output_settings:
  diagnostics_names: extc
  evaluate_past: yes
  variables_in_scores:
  - state
  - parameter
  generate_plot: yes
  diagnostics_daily:
    names:
    - Tot Inflow Vol
    - flow
    - temp
    - salt
    save_names:
    - inflow
    - overflow_flow
    - overflow_temp
    - overflow_salt
    file:
    - lake.csv
    - overflow.csv
    - overflow.csv
    - overflow.csv
    depth:
    - .na
    - .na
    - .na
    - .na
    - .na
    - .na
    - .na
    - .na
---

## configure_run.yml

The configure_run file is modified during the generation of the forecast (see the workflow [README](../../workflows/glm_flare_v3/README.md) and `sim_name` is modified during the generation of the scenarios.

## glm3.nml

Make sure the crest dimensions are set in the morphometry and outflow sections. In addition the output needs to have the overflow set. The num_outlets is set to 1, but the outflow_factor is set to 0.

---
&output
   out_dir = "./"
   out_fn  = 'output'
   nsave   = 1
   csv_lake_fname = 'lake'
   csv_outlet_allinone = .false.
   csv_outlet_fname = 'outlet_'
   csv_outlet_nvars = 3
   csv_outlet_vars = 'flow', 'temp', 'salt'
   csv_ovrflw_fname = "overflow"
/
&outflow
   num_outlet     = 1
   outlet_type    = 1
   flt_off_sw     = .false.
   outl_elvs      = -1
   bsn_len_outl   = 35000    !as in morphom, estim
   bsn_wid_outl   = 40000    !as in morphom, estim
   outflow_fl     = 'outflow.csv'
   outflow_factor = 0
   crest_width = 2000  
   crest_factor = 1
/
---

## observations_config.csv

Depth, temp, and salt are all included in the data assimilation. Depth `multi_depth = 0`.

## parameter_calibration_config.csv

Parameter tuning occurs for `crest_elev` and `lw_factor` (`fix_par = 0`) but sediment zone temperatures are fixed.
