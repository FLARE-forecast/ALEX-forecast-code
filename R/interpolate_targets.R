#' @title Interpolate observations to a continuous time series
#' @details Generating an interpolated target that can be used as a driver (could be used as inflow/outflow or other datafrmaes in the targets format)
#' @param targets name of the target file csv
#' @param lake_directory FLARE working directory eg. ~home/rqthomas/FCRE-forecast-code
#' @param targets_dir where are the targets?
#' @param site_id code for site being forecasted
#' @param variables optional vector of variables to generate the interpolation for. Default is no filtering (all variables included from targets)
#' @param groups which groups (in addition to the variables) should be used (e.g. depth, site_id, inflow_name etc.)
#' @param method interpolation method to be used (linear, spline or stine)
#' @return dataframe of interpolated time series
#' @export

interpolate_targets <- function(targets, 
                                lake_directory,
                                targets_dir = 'targets',
                                site_id,
                                variables = NULL,
                                groups = NULL,
                                method = 'linear') {
  # read in data
  df <- readr::read_csv(file.path(lake_directory, targets_dir, site_id, targets),
                        show_col_types = F)
  
  
  # which variables are we using?
  if (is.null(variables)) {
    filter_vars  <- dplyr::distinct(df,variable) |> 
      pull(variable)
  } else {
    filter_vars <- variables
  }
  
  # is depth a column in these targets?
  if (is.null(groups)) {
    grouping_vars <- c('variable',  'site_id')
  }else {
    grouping_vars <- c('variable', 'site_id', groups)
  }
  
  
  
  forecast_start <- as.Date(config$run_config$forecast_start_datetime)
  
  if(max(df$datetime) < forecast_start){
    date_range <- seq.Date(as.Date(max(df$datetime)), forecast_start, by = 'day')
    date_range <- date_range[date_range != max(df$datetime)]
    
    persistence_value <- df |>  
      filter(datetime == max(datetime))  |>  
      pull(observation)
    
    persistence_df <- data.frame(site_id = 'ALEX', 
                                 datetime = date_range,
                                 variable = "FLOW",
                                 observation = persistence_value)
    
    # generate an interpolation
    df_interp <- df |>
      mutate(datetime = as_date(datetime)) |> 
      bind_rows(persistence_df) |>
      tsibble::as_tsibble(key = all_of(grouping_vars), index = datetime) |> 
      tsibble::fill_gaps() |> 
      tibble::as_tibble() |> 
      dplyr::filter(variable %in% filter_vars) |> 
      dplyr::group_by(dplyr::pick(any_of(grouping_vars))) |> 
      dplyr::arrange(dplyr::pick(any_of(grouping_vars), datetime)) |> 
      dplyr::mutate(observation = imputeTS::na_interpolation(observation,option = method)) |> 
      dplyr::ungroup()
  } else {
    # generate an interpolation
    df_interp <- df |>
      mutate(datetime = as_date(datetime)) |> 
      tsibble::as_tsibble(key = all_of(grouping_vars), index = datetime) |> 
      tsibble::fill_gaps() |> 
      tibble::as_tibble() |> 
      dplyr::filter(variable %in% filter_vars) |> 
      dplyr::group_by(dplyr::pick(any_of(grouping_vars))) |> 
      dplyr::arrange(dplyr::pick(any_of(grouping_vars), datetime)) |> 
      dplyr::mutate(observation = imputeTS::na_interpolation(observation,option = method)) |> 
      dplyr::ungroup()
  }
  
  
  # # generate an interpolation
  # df_interp <- df |>
  #   mutate(datetime = as_date(datetime)) |> 
  #   tsibble::as_tsibble(key = all_of(grouping_vars), index = datetime) |> 
  #   tsibble::fill_gaps() |> 
  #   tibble::as_tibble() |> 
  #   dplyr::filter(variable %in% filter_vars) |> 
  #   dplyr::group_by(dplyr::pick(any_of(grouping_vars))) |> 
  #   dplyr::arrange(dplyr::pick(any_of(grouping_vars), datetime)) |> 
  #   dplyr::mutate(observation = imputeTS::na_interpolation(observation,option = method)) |> 
  #   dplyr::ungroup()
  
  return(df_interp)
  
}
