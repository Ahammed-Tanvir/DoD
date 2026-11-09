local({
   need <- c("data.table", "ggplot2", "lightgbm", "ranger", "quantreg", "FNN", "mgcv", "earth", "nnet", "forecast")
   miss <- need[!vapply(need, function(p) suppressMessages(requireNamespace(p, quietly = TRUE)), TRUE)]
   if (length(miss)) install.packages(miss, repos = "https://cloud.r-project.org")
})
suppressPackageStartupMessages({
   library(data.table)
   library(ggplot2)
})

quantiles <- c(
   0.01, 0.025, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45,
   0.5,
   0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 0.975, 0.99
)
horizons <- 1:4

BOX <- "/Users/tanvirahammed/Library/CloudStorage/Box-Box/BoxPHI-PHMR Projects"

path_truth_dir  <- file.path(BOX, "Data/DoD Data/Data Files")
path_truth_file <- NULL
path_mapping    <- file.path(BOX, "Data/DoD Data/Auxiliary Information/afhsd_region_dmisid_mapping.csv")
path_county     <- file.path(BOX, "Data/DoD Data/Auxiliary Information/afhsd_region_county_mapping.csv")
path_nssp       <- "auto"

nssp_dir        <- file.path(BOX, "Tanvir/DoD/NSSP")
path_backtest   <- file.path(BOX, "Tanvir/DoD/Forecasts")
output_dir      <- file.path(BOX, "Tanvir/DoD")
submit_dir      <- file.path(BOX, "Tanvir/DoD/Submitted")

DISEASES         <- c("flu", "cov", "rsv")
FORECAST_REGIONS <- "table2"
focus_regions    <- NULL

team_abbr    <- "DMAPRIME"
model_abbr   <- "QEns"
team_name    <- "CPHMR, Clemson University"
model_name   <- "Pooled quantile ensemble"
contributors <- "Tanvir Ahammed (Clemson University, South Carolina) <tahamme@g.clemson.edu>"
website_url  <- "https://github.com/Ahammed-Tanvir/DoD"
license_txt  <- "CC-BY-4.0"
designation  <- "primary"
MODEL_LABEL  <- paste0(team_abbr, "-", model_abbr)

point_interval <- c(0.025, 0.975)
value_digits   <- 4
file_suffix    <- ""
ONE_FILE       <- TRUE

USE_BACKTEST_SETTINGS <- c(flu = TRUE, cov = TRUE, rsv = TRUE)
DEFAULT_SETTINGS <- data.table(
   disease = c("flu", "cov", "rsv"),
   data    = "dod",
   members = "gbqr+qrf+lqr",
   combine = "median",
   recal   = c("widen", "none", "widen"),
   widen   = c(1.15, NA, 1.05)
)
MODELS      <- c("gbqr", "qrf", "lqr", "ar", "trend", "xt", "knn", "seasonal", "growthqr",
                 "gam", "mars", "mlp", "ets", "arima", "theta")
COMBINE     <- "median"; RECALIBRATE <- "none"
WIDEN       <- c(cov = 1, flu = 1, rsv = 1)
AUGMENT_CIV <- FALSE
NSSP_HSA    <- FALSE
RECONCILE   <- TRUE
SHRINK_TAU  <- Inf
COHERENCE   <- "off"
RECON_WINDOW <- 8L
ANTILAG     <- TRUE
TREND_AWARE <- TRUE
USE_SELECTION <- TRUE

MAX_TRAIN_ROWS <- 300000
GBQR_ROUNDS    <- 250
N_THREADS      <- max(1L, parallel::detectCores() - 1L)
SEED           <- 2026
options(dod.threads = N_THREADS)
set.seed(SEED)

SAVE_SUBMISSION <- TRUE
SAVE_PLOTS      <- TRUE

`%||%` <- function(a, b) if (is.null(a)) b else a

QL    <- round(quantiles, 3)

MED   <- which(QL == 0.5)

MAX_K <- 5L

SW    <- c(6L, 46L)

AR_P  <- 6L

AR_SIMS <- 1000L

AUX_RE <- "^(civ|nssp):"

NSSP_COLS <- c(cov = "percent_visits_covid", flu = "percent_visits_influenza", rsv = "percent_visits_rsv")

DISEASE <- list(
  cov = list(name = "COVID-19", y = "mhs_cov_percent", enc = "mhs_cov_encounters", seasonal = FALSE,
             drop_seasons = integer(0), start = "2020-07-01",

             alt = list(label = "COVID recent years, no time-of-year inputs", start = "2022-07-01",
                        drop = c("season_week", "wk_xmas", "sin1", "cos1")),
             cov = c(case = "mhs_covid_case_rate", civpct = "civ_cov_percent",
                     ww = "civ_covid_wastewater_level", civcase = "civ_covid_case_rate")),
  flu = list(name = "Influenza", y = "mhs_flu_percent", enc = "mhs_flu_encounters", seasonal = TRUE,
             drop_seasons = 2020L, start = NULL,
             cov = c(case = "mhs_flu_case_rate", civpct = "civ_flu_percent",
                     ww = "civ_flu_wastewater_level", civcase = "civ_flu_case_rate")),
  rsv = list(name = "RSV", y = "mhs_rsv_percent", enc = "mhs_rsv_encounters", seasonal = TRUE,
             drop_seasons = 2020L, start = NULL,
             cov = c(case = "mhs_rsv_case_rate", civpct = "civ_rsv_percent",
                     ww = "civ_rsv_wastewater_level", civcase = "civ_rsv_case_rate"))
)

TABLE2_REGIONS <- c(
  "DHN Central", "DHN Atlantic", "DHN East", "DHN Continental", "DHN Pacific Rim", "DHN West",
  "DHN National Capital Region", "National Capital Region", "DHN Indo-Pacific", "Tidewater",
  "San Antonio", "San Diego", "DHN Europe", "Puget Sound", "North Carolina, Central", "Hawaii",
  "Colorado", "Central Texas", "El Paso", "North Carolina, Coastal", "Florida Panhandle",
  "Southwest Kentucky", "Southwest Georgia", "Alaska", "Jacksonville", "Low Country",
  "Central South Carolina", "Okinawa/Kadena", "Landstuhl/Ramstein", "Great Lakes", "Augusta",
  "Southwest Oklahoma", "Las Vegas", "Charleston", "Ozarks", "Allgood", "Wright-Patterson AFB",
  "Yokosuka", "New England", "Gulf Coast", "Sacramento", "Kansas", "Bavaria", "Upstate New York",
  "Garden State", "Central Virginia", "Southern Arizona", "United Kingdom", "Tinker AFB", "Luke AFB",
  "Hill AFB", "Agana", "Central Louisiana", "Offutt AFB", "MacDill AFB", "Scott AFB",
  "Twentynine Palms", "Ft Leavenworth", "Central Kentucky", "West Point", "Los Angeles",
  "Ft Novosel", "Lemoore", "Robins AFB", "Southeast Pennsylvania", "Little Rock", "Maxwell AFB",
  "California Desert", "Minot AFB", "Barksdale AFB", "Redstone Arsenal", "Patrick SFB", "Whiteman AFB")

REGION_STATE <- c(
  "National Capital Region" = "MD", "Tidewater" = "VA", "San Antonio" = "TX", "San Diego" = "CA",
  "Puget Sound" = "WA", "North Carolina, Central" = "NC", "Hawaii" = "HI", "Colorado" = "CO",
  "Central Texas" = "TX", "El Paso" = "TX", "North Carolina, Coastal" = "NC", "Florida Panhandle" = "FL",
  "Southwest Kentucky" = "KY", "Southwest Georgia" = "GA", "Alaska" = "AK", "Jacksonville" = "FL",
  "Low Country" = "GA", "Central South Carolina" = "SC", "Great Lakes" = "IL", "Augusta" = "GA",
  "Southwest Oklahoma" = "OK", "Las Vegas" = "NV", "Charleston" = "SC", "Ozarks" = "MO",
  "Wright-Patterson AFB" = "OH", "New England" = "MA", "Gulf Coast" = "LA", "Sacramento" = "CA",
  "Kansas" = "KS", "Upstate New York" = "NY", "Garden State" = "NJ", "Central Virginia" = "VA",
  "Southern Arizona" = "AZ", "Tinker AFB" = "OK", "Luke AFB" = "AZ", "Hill AFB" = "UT", "Agana" = "GU",
  "Central Louisiana" = "LA", "Offutt AFB" = "NE", "MacDill AFB" = "FL", "Scott AFB" = "MO",
  "Twentynine Palms" = "CA", "Ft Leavenworth" = "MO", "Central Kentucky" = "KY", "West Point" = "NY",
  "Los Angeles" = "CA", "Ft Novosel" = "AL", "Lemoore" = "CA", "Robins AFB" = "GA",
  "Southeast Pennsylvania" = "PA", "Little Rock" = "AR", "Maxwell AFB" = "AL", "California Desert" = "CA",
  "Minot AFB" = "ND", "Barksdale AFB" = "LA", "Redstone Arsenal" = "AL", "Patrick SFB" = "FL",
  "Whiteman AFB" = "MO")

STATE_NAMES <- c(setNames(state.name, state.abb), DC = "District of Columbia", GU = "Guam")

METHODS_TXT <- "Ensemble of quantile gradient boosting, quantile forests and linear quantile regression, pooled across regions on a 4th-root scale; trend, seasonal and NSSP inputs; recalibrated."

read_any <- function(path) {
  if (!file.exists(path)) stop("File not found: ", normalizePath(path, mustWork = FALSE), call. = FALSE)
  ext <- tolower(tools::file_ext(path))
  d <- switch(ext,
    xlsx = , xls = {
      if (!requireNamespace("readxl", quietly = TRUE)) stop("install.packages(\"readxl\") to read Excel files")
      as.data.table(readxl::read_excel(path, guess_max = 1e5))
    },
    parquet = if (requireNamespace("arrow", quietly = TRUE)) as.data.table(arrow::read_parquet(path))
              else as.data.table(nanoparquet::read_parquet(path)),
    fread(path, na.strings = c("", "NA", "NULL", "N/A", "null", "."), encoding = "UTF-8"))
  setnames(d, tolower(trimws(names(d))))
  d
}

parse_dates <- function(x) {
  if (inherits(x, c("Date", "POSIXt"))) return(as.IDate(as.Date(x)))
  if (is.numeric(x)) return(as.IDate(as.Date(x, origin = "1899-12-30")))
  x <- trimws(as.character(x))
  for (f in c("%Y-%m-%d", "%m/%d/%Y", "%Y/%m/%d", "%d%b%Y", "%d-%b-%Y", "%b %d, %Y", "%m/%d/%y")) {
    d <- as.Date(x, format = f)
    if (mean(!is.na(d[!is.na(x)])) > 0.95) return(as.IDate(d))
  }
  stop("Could not read the date column; example values: ", paste(head(x, 3), collapse = ", "), call. = FALSE)
}

mmwr_week1_start <- function(year) { j <- as.IDate(sprintf("%d-01-04", year)); j - (wday(j) - 1L) }

mmwr_week_end <- function(year, week) mmwr_week1_start(year) + 7L * (as.integer(week) - 1L) + 6L

mmwr_of <- function(d) {
  start <- as.IDate(d) - (wday(as.IDate(d)) - 1L)
  y <- year(start + 3L)
  list(year = y, week = as.integer(start - mmwr_week1_start(y)) %/% 7L + 1L)
}

mdy_str   <- function(d) sprintf("%d/%d/%d", month(d), mday(d), year(d))

dmy_tag   <- function(d) sprintf("%02d%s%d", mday(d), toupper(month.abb[month(d)]), year(d))

week_tag  <- function(d) { w <- mmwr_of(d); sprintf("%d-EW%02d", w$year, w$week) }

TRUTH_RE <- "^([0-9]{4})-EW([0-9]{1,2})-truth_regions_ext_([0-9]{2}[A-Za-z]{3}[0-9]{4}).*\\.csv$"

find_data_file <- function(dir) {
  if (!dir.exists(dir)) stop("Data folder not found: ", dir,
                                      "\n(Is Box Drive running and the folder synced?)", call. = FALSE)
  f <- list.files(dir, pattern = TRUTH_RE, ignore.case = TRUE)
  f <- f[!grepl("^~\\$|^\\.", f)]
  if (!length(f)) stop("No file like 2026-EW40-truth_regions_ext_10OCT2026.csv in ", dir, call. = FALSE)
  yr <- as.integer(sub(TRUTH_RE, "\\1", f, ignore.case = TRUE))
  wk <- as.integer(sub(TRUTH_RE, "\\2", f, ignore.case = TRUE))
  mt <- as.numeric(file.mtime(file.path(dir, f)))
  f <- f[order(yr, wk, mt, decreasing = TRUE)]

  file.path(dir, f[1])
}

to_num <- function(x) {
  if (is.numeric(x)) return(as.numeric(x))
  suppressWarnings(as.numeric(gsub("[%,[:space:]]", "", as.character(x))))
}

load_dod <- function(path) {
  d <- read_any(path)
  if (!"region" %in% names(d)) stop("The data file has no 'region' column.", call. = FALSE)
  d[, region := trimws(as.character(region))]
  if ("date" %in% names(d)) d[, date := parse_dates(date)]
  else if (all(c("year", "epiweek") %in% names(d))) d[, date := mmwr_week_end(as.integer(year), as.integer(epiweek))]
  else stop("The data file needs a 'date' column (or 'year' + 'epiweek').", call. = FALSE)
  if (any(wday(d$date) != 7L, na.rm = TRUE)) {
    d[, date := date + (7L - wday(date))]
  }
  used <- unique(c(unlist(lapply(DISEASE, function(s) c(s$y, s$enc, s$cov))),
                   "mhs_population", "mhs_tot_encounters"))
  for (v in intersect(used, names(d))) set(d, j = v, value = to_num(d[[v]]))
  for (s in DISEASE) if (s$enc %in% names(d) && "mhs_tot_encounters" %in% names(d)) {
    calc <- 100 * d[[s$enc]] / d$mhs_tot_encounters
    calc[!is.finite(calc)] <- NA
    if (!s$y %in% names(d)) set(d, j = s$y, value = calc)
    else { i <- which(is.na(d[[s$y]]) & !is.na(calc)); if (length(i)) set(d, i = i, j = s$y, value = calc[i]) }
  }
  d <- d[!is.na(date) & !is.na(region) & region != ""]
  d <- unique(d, by = c("region", "date"), fromLast = TRUE)
  setorder(d, region, date)
  d[]
}

norm_name <- function(x) gsub("[^a-z0-9]", "", tolower(x))

pick_regions <- function(spec, available) {
  if (identical(spec, "all")) return(sort(available))
  want <- if (identical(spec, "table2")) TABLE2_REGIONS else spec
  m <- match(norm_name(want), norm_name(available))
  available[m[!is.na(m)]]
}

load_parent_map <- function(path, available) {
  if (is.null(path)) return(NULL)
  m <- tryCatch(read_any(path), error = function(e) NULL)
  if (is.null(m) || !all(c("afhsd_region", "dhn") %in% names(m))) return(NULL)
  m <- m[!is.na(afhsd_region) & !is.na(dhn), .N, by = .(r = trimws(afhsd_region), p = trimws(dhn))]
  m[, share := N / sum(N), by = r]
  m <- m[order(-N)][, .SD[1], by = r]
  find <- function(x) { i <- match(norm_name(x), norm_name(available))
    j <- match(norm_name(paste("DHN", x)), norm_name(available)); available[fifelse(is.na(i), j, i)] }
  out <- unique(data.table(location = find(m$r), parent = find(m$p), pure = m$share >= 0.999))[
    !is.na(location) & !is.na(parent) & location != parent]
  if (nrow(out) == 0) return(NULL)

  out
}

NSSP_ID <- "rdmq-nq56"

fetch_nssp <- function(dir, query_url = sprintf("https://data.cdc.gov/resource/%s.csv", NSSP_ID),
                       export_url = sprintf("https://data.cdc.gov/api/views/%s/rows.csv?accessType=DOWNLOAD", NSSP_ID)) {
   dir.create(dir, recursive = TRUE, showWarnings = FALSE)
   saved <- sort(list.files(dir, pattern = "^nssp_state_[0-9]{4}-[0-9]{2}-[0-9]{2}\\.csv$", full.names = TRUE), decreasing = TRUE)
   today <- file.path(dir, sprintf("nssp_state_%s.csv", Sys.Date()))
   if (file.exists(today)) return(today)
   usable <- function(f) { x <- tryCatch(fread(f), error = function(e) NULL)
      !is.null(x) && nrow(x) > 100 && all(c("week_end", "geography", "trend_source") %in% names(x)) }
   old_to <- options(timeout = max(600, getOption("timeout"))); on.exit(options(old_to), add = TRUE)
   tmp <- tempfile(fileext = ".csv")

   q <- paste0(query_url, "?$where=", utils::URLencode("trend_source='State'", reserved = TRUE), "&$limit=5000000")
   got <- tryCatch({ utils::download.file(q, tmp, quiet = TRUE, mode = "wb"); usable(tmp) },
                   error = function(e) FALSE, warning = function(w) FALSE)

   if (!got) got <- tryCatch({
      full <- tempfile(fileext = ".csv"); utils::download.file(export_url, full, quiet = TRUE, mode = "wb")
      x <- fread(full); setnames(x, tolower(gsub("[^A-Za-z0-9]+", "_", trimws(names(x)))))
      if ("trend_source" %in% names(x)) x <- x[trend_source == "State"]
      fwrite(x, tmp); usable(tmp) }, error = function(e) FALSE, warning = function(w) FALSE)
   if (got) {
      file.copy(tmp, today, overwrite = TRUE)

      return(today)
   }
   if (length(saved)) return(saved[1])

   NULL
}

load_nssp <- function(path, include_hsa = FALSE) {
  if (is.null(path)) return(NULL)
  d <- tryCatch(read_any(path), error = function(e) NULL)
  if (is.null(d)) return(NULL)
  if (!all(c("week_end", "geography", "trend_source") %in% names(d))) return(NULL)
  keep <- if (include_hsa && "hsa_nci_id" %in% names(d)) c("State", "HSA") else "State"
  d <- d[trend_source %in% keep]
  d[, date := parse_dates(week_end)]
  d[, `:=`(location = fifelse(trend_source == "State", paste0("nssp:", geography), paste0("nssp:hsa", d[["hsa_nci_id"]] %||% "")),
           is_state = trend_source == "State")]
  out <- rbindlist(lapply(names(NSSP_COLS), function(dz) {
    col <- NSSP_COLS[[dz]]
    if (!col %in% names(d)) return(NULL)
    x <- d[, .(disease = dz, location, state = geography, is_state, date, y = to_num(get(col)))][!is.na(y) & !is.na(date)]
    unique(x, by = c("location", "date"), fromLast = TRUE)
  }))
  if (!nrow(out)) return(NULL)

  out
}

load_region_states <- function(path, available) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  m <- tryCatch(read_any(path), error = function(e) NULL)
  if (is.null(m) || !all(c("region", "state") %in% names(m))) return(NULL)
  m <- data.table(r = trimws(m$region), st = trimws(as.character(m$state)),
                  pop = if ("population" %in% names(m)) to_num(m$population) else 1)
  m[nchar(st) == 2, st := unname(STATE_NAMES[toupper(st)])]
  m <- m[!is.na(st) & st != "", .(w = sum(pmax(pop, 0), na.rm = TRUE)), by = .(r, st)]
  m[, w := if (sum(w) > 0) w / sum(w) else 1 / .N, by = r]
  out <- m[, .(location = available[match(norm_name(r), norm_name(available))], state = st, w)][!is.na(location)]
  if (!nrow(out)) return(NULL)
  out
}

region_state_map <- function(locations) {
  if (exists("REGION_STATES") && !is.null(REGION_STATES)) return(REGION_STATES[location %in% locations])
  i <- match(norm_name(locations), norm_name(names(REGION_STATE)))
  m <- data.table(location = locations, state = unname(STATE_NAMES[REGION_STATE[i]]), w = 1)
  m[!is.na(state)]
}

data_file_used <- if (is.null(path_truth_file)) find_data_file(path_truth_dir) else path_truth_file
raw <- load_dod(data_file_used)

target_cols <- vapply(DISEASE[DISEASES], `[[`, "", "y")
DISEASES    <- DISEASES[target_cols %in% names(raw)]
target_cols <- target_cols[target_cols %in% names(raw)]
if (!length(DISEASES)) stop("None of mhs_cov_percent / mhs_flu_percent / mhs_rsv_percent are in the file.")

latest_week  <- max(raw[rowSums(!is.na(raw[, ..target_cols])) > 0, date])

forecast_regions <- pick_regions(FORECAST_REGIONS, unique(raw$region))
parent_map       <- load_parent_map(path_mapping, unique(raw$region))
REGION_STATES    <- load_region_states(path_county, unique(raw$region))
nssp             <- load_nssp(if (identical(path_nssp, "auto")) fetch_nssp(nssp_dir) else path_nssp, NSSP_HSA)

season_of   <- function(d) { d <- as.IDate(d); ifelse(month(d) >= 8L, year(d), year(d) - 1L) }

season_week <- function(d) { d <- as.IDate(d); as.integer(d - as.IDate(sprintf("%d-08-01", season_of(d)))) %/% 7L + 1L }

weeks_from_xmas <- function(d) {
  d <- as.IDate(d); x <- as.IDate(sprintf("%d-12-25", season_of(d)))
  as.integer(d - (x + (7L - wday(x)))) %/% 7L
}

transform_stats <- function(df, cutoff) {
  d <- df[date < as.IDate(cutoff) & !is.na(y)]
  d[, z := pmax(y, 0)^0.25]
  s <- d[, .(p95 = max(quantile(z, 0.95), 0.3)), by = location]
  d <- merge(d, s, by = "location")
  merge(s, d[, .(mu = mean(z / p95)), by = location], by = "location")
}

to_z   <- function(y, p95, mu) pmax(y, 0)^0.25 / p95 - mu

from_z <- function(z, p95, mu) pmax((z + mu) * p95, 0)^4

noise_proxy <- function(df, stats, cutoff) {
  d <- merge(df[date < as.IDate(cutoff)], stats, by = "location")
  setorder(d, location, date)
  d[, z := to_z(y, p95, mu)]
  d[, dz := z - shift(z), by = location]
  d[, .(noise = median(abs(dz), na.rm = TRUE)), by = location]
}

fill_gaps <- function(z, maxgap = 2L) {
  ok <- which(!is.na(z)); if (length(ok) < 2L) return(z)
  zi <- approx(ok, z[ok], xout = seq_along(z), rule = 1)$y
  r <- rle(is.na(z)); zi[rep(r$values & r$lengths > maxgap, r$lengths)] <- NA
  zi
}

TAYLOR <- list(c(2, 4), c(2, 6), c(1, 3), c(1, 5))

taylor_proj <- function(deg, w) {
  u <- seq(-(w - 1), 0)
  X <- sapply(0:deg, function(c) u^c / factorial(c))
  solve(crossprod(X), t(X))
}

tp_apply <- function(z, P, row) { w <- ncol(P); Reduce(`+`, lapply(seq_len(w), function(j) P[row, j] * shift(z, w - j))) }

build_panel <- function(df, stats) {
  d <- df[location %in% stats$location, .(location, date, y)]
  grid <- d[, .(date = as.IDate(seq(as.Date(min(date)), as.Date(max(date)), by = 7))), by = location]
  d <- merge(grid, d, by = c("location", "date"), all.x = TRUE)
  d <- merge(d, stats, by = "location")
  setorder(d, location, date)
  d[, z := to_z(y, p95, mu)]
  d[, level := fill_gaps(z), by = location]
  base <- "level"
  for (tp in TAYLOR) {
    deg <- tp[1]; w <- tp[2]; P <- taylor_proj(deg, w)
    for (c in 0:deg) {
      nm <- sprintf("tp_d%d_w%d_c%d", deg, w, c)
      d[, (nm) := tp_apply(level, P, c + 1), by = location]
      base <- c(base, nm)
    }
  }
  d[, rm_w2 := frollmean(level, 2), by = location]
  d[, rm_w4 := frollmean(level, 4), by = location]
  base <- c(base, "rm_w2", "rm_w4")
  for (L in 1:2) for (b in base) d[, (paste0(b, "_lag", L)) := shift(get(b), L), by = location]
  d[, `:=`(season = season_of(date), season_week = season_week(date), wk_xmas = weeks_from_xmas(date))]
  for (i in 0:(AR_P - 1L)) d[, (sprintf("ar_l%d", i)) := shift(level, i), by = location]
  d[, z_next := shift(z, -1L), by = location]
  d[]
}

covariate_tables <- function(raw, spec, dis, nssp, locations) {
  tabs <- list()
  for (role in names(spec$cov)) {
    col <- spec$cov[[role]]
    if (col %in% names(raw)) tabs[[role]] <- raw[!is.na(get(col)) & region %in% locations, .(location = region, date, x = get(col))]
  }
  if (!is.null(nssp)) {
    st <- nssp[disease == dis & is_state == TRUE, .(state, date, x = y)]
    map <- region_state_map(locations)
    if (nrow(st) && nrow(map)) tabs$nsst <- merge(map, st, by = "state", allow.cartesian = TRUE)[
      , .(x = sum(w * x) / sum(w)), by = .(location, date)]
  }
  Filter(function(t) nrow(t) >= 20, tabs)
}

add_covariates <- function(panel, tabs, cutoff) {
  P3 <- taylor_proj(1, 3); P5 <- taylor_proj(1, 5)
  for (role in names(tabs)) {
    x <- copy(tabs[[role]])
    pos <- all(x$x >= 0)
    x[, xt := if (pos) x^0.25 else asinh(x)]
    s <- x[date < cutoff, .(m = mean(xt), s = max(sd(xt), 1e-3)), by = location][!is.na(s)]
    x <- merge(x, s, by = "location")
    if (nrow(x) == 0) next
    x[, v := (xt - m) / s]
    lv <- paste0(role, "_lvl")
    panel <- merge(panel, unique(x[, .(location, date, v)], by = c("location", "date")), by = c("location", "date"), all.x = TRUE)
    setorder(panel, location, date)
    panel[, (lv) := fill_gaps(v), by = location]
    panel[, (paste0(role, "_s3")) := tp_apply(get(lv), P3, 2), by = location]
    panel[, (paste0(role, "_s5")) := tp_apply(get(lv), P5, 2), by = location]
    panel[, v := NULL]
  }
  panel
}

make_meta <- function(df, raw, stats, cutoff) {
  r <- raw[date < cutoff & region %in% stats$location]
  m <- data.table(location = stats$location)
  if ("mhs_population" %in% names(r))
    m <- merge(m, r[, .(log_pop = log10(pmax(median(mhs_population, na.rm = TRUE), 1))), by = .(location = region)], by = "location", all.x = TRUE)
  if ("mhs_tot_encounters" %in% names(r))
    m <- merge(m, r[date >= cutoff - 365L, .(log_enc = log10(pmax(median(mhs_tot_encounters, na.rm = TRUE), 1))), by = .(location = region)], by = "location", all.x = TRUE)
  m <- merge(m, noise_proxy(df, stats, cutoff), by = "location", all.x = TRUE)
  m[, is_aux := as.integer(grepl(AUX_RE, location))]
  for (v in names(m)) if (is.numeric(m[[v]])) set(m, i = which(!is.finite(m[[v]])), j = v, value = NA_real_)
  m
}

add_context <- function(panel, parent_map) {
  g <- panel[!is.na(level) & !grepl(AUX_RE, location),
             .(g_level = mean(level), g_slope = mean(tp_d2_w4_c1, na.rm = TRUE)), by = date]
  g[!is.finite(g_slope), g_slope := NA_real_]
  panel <- merge(panel, g, by = "date", all.x = TRUE)
  if (!is.null(parent_map)) {
    pp <- panel[, .(parent = location, date, par_level = level, par_slope = tp_d2_w4_c1)]
    panel <- merge(panel, parent_map, by = "location", all.x = TRUE)
    panel <- merge(panel, pp, by = c("parent", "date"), all.x = TRUE)
    panel[, parent := NULL]
  }
  setorder(panel, location, date)
  panel
}

build_features <- function(df, raw, stats, spec, dis, cutoff, parent_map, nssp) {
  panel <- build_panel(df, stats)
  dod_locs <- unique(panel$location[!grepl(AUX_RE, panel$location)])
  panel <- add_covariates(panel, covariate_tables(raw, spec, dis, nssp, dod_locs), cutoff)
  panel <- merge(panel, make_meta(df, raw, stats, cutoff), by = "location", all.x = TRUE)
  add_context(panel, parent_map)
}

add_fourier <- function(d) {
  a <- 2 * pi * (d$season_week + d$k) / 52
  d[, `:=`(sin1 = sin(a), cos1 = cos(a))]
}

origin_rows <- function(panel, max_date, spec) {
  p <- panel[date <= max_date & !is.na(z) & !is.na(tp_d2_w6_c0)]
  if (spec$seasonal) p <- p[season_week >= SW[1] & season_week <= SW[2] & !season %in% spec$drop_seasons]
  if (!is.null(spec$start)) p <- p[date >= as.IDate(spec$start)]
  p
}

make_training_rows <- function(panel, max_date, spec, ks = 1:MAX_K) {
  p <- origin_rows(panel, max_date, spec)
  zl <- panel[!is.na(z), .(location, tdate = date, z_target = z)]
  r <- rbindlist(lapply(ks, function(k) { x <- copy(p); x[, `:=`(k = k, tdate = date + 7L * k)]; x }))
  r <- merge(r[tdate <= max_date], zl, by = c("location", "tdate"))
  r[, delta := z_target - level]
  add_fourier(r)
  r[]
}

cap_rows <- function(tr, n_max = MAX_TRAIN_ROWS, seed = 1) {
  if (nrow(tr) <= n_max) return(tr)
  set.seed(seed)
  aux <- which(tr$is_aux %in% 1L); dod <- setdiff(seq_len(nrow(tr)), aux)
  keep <- c(dod, aux[sample.int(length(aux), max(0L, min(length(aux), n_max - length(dod))))])
  tr[sort(keep)]
}

feature_cols <- function(panel) {
  c(grep("^(level|tp_|rm_)", names(panel), value = TRUE),
    intersect(c("season_week", "wk_xmas", "log_pop", "log_enc", "noise", "is_aux", "k",
                "g_level", "g_slope", "par_level", "par_slope"), c(names(panel), "k")),
    grep("^(case|civpct|ww|civcase|nsst)_(lvl|s3|s5)$", names(panel), value = TRUE))
}

LQR_COLS <- c("level", "tp_d2_w4_c1", "tp_d2_w4_c2", "tp_d2_w6_c1", "tp_d2_w6_c2", "g_slope", "noise", "sin1", "cos1")

spec_for <- function(spec, setting) {
  if (identical(setting, "alt") && !is.null(spec$alt)) {
    spec$start <- spec$alt$start %||% spec$start
    spec$drop_feats <- spec$alt$drop
  }
  spec
}

model_cols <- function(panel, spec) setdiff(feature_cols(panel), spec$drop_feats)

nthreads <- function() getOption("dod.threads", 1L)

fit_gbqr <- function(tr, cols, nrounds = getOption("dod.gbqr_rounds", GBQR_ROUNDS), seed = 1) {
  ds <- lightgbm::lgb.Dataset(as.matrix(tr[, ..cols]), label = tr$delta, free_raw_data = FALSE)
  lapply(QL, function(q) lightgbm::lgb.train(
    params = list(objective = "quantile", alpha = q, learning_rate = 0.05, num_leaves = 31,
                  min_data_in_leaf = 40, bagging_fraction = 0.7, bagging_freq = 1,
                  feature_fraction = 0.8, verbose = -1, num_threads = nthreads(), seed = seed,
                  deterministic = TRUE, force_row_wise = TRUE),
    data = ds, nrounds = nrounds))
}

pred_gbqr <- function(models, X) matrix(sapply(models, function(m) predict(m, X)), nrow = nrow(X))

impute <- function(X, fill = -99) { X[is.na(X)] <- fill; X }

fit_qrf <- function(tr, cols, n_max = getOption("dod.qrf_rows", 150000), seed = 1) {
  set.seed(seed)
  tr <- if (nrow(tr) > n_max) tr[sample(.N, n_max)] else tr
  ranger::ranger(x = impute(as.data.frame(tr[, ..cols])), y = tr$delta, num.trees = getOption("dod.qrf_trees", 300),
                 min.node.size = 20, mtry = min(12L, length(cols)), sample.fraction = 0.5,
                 quantreg = TRUE, num.threads = nthreads(), seed = seed, verbose = FALSE)
}

pred_qrf <- function(m, X) {
  set.seed(7)
  predict(m, data = impute(as.data.frame(X)), type = "quantiles", quantiles = QL, verbose = FALSE)$predictions
}

fit_lqr <- function(tr, cols = LQR_COLS, n_max = 60000, seed = 1) {
  set.seed(seed)
  lapply(seq_len(MAX_K), function(kk) {
    d <- tr[k == kk]
    if (nrow(d) < 50) return(NULL)
    if (nrow(d) > n_max) d <- d[sample(.N, n_max)]
    X <- impute(as.matrix(d[, ..cols]), 0)
    keep <- cols[apply(X, 2, sd) > 1e-8]
    X <- cbind(1, X[, keep, drop = FALSE])
    B <- sapply(QL, function(q) tryCatch(quantreg::rq.fit(X, d$delta, tau = q, method = "fn")$coefficients,
                                         error = function(e) quantreg::rq.fit(X, d$delta, tau = q, method = "br")$coefficients))
    list(cols = keep, B = B)
  })
}

pred_lqr <- function(models, X, k) {
  out <- matrix(NA_real_, nrow(X), length(QL))
  for (kk in unique(k)) {
    m <- models[[kk]] %||% models[[max(which(!vapply(models, is.null, TRUE)))]]
    i <- which(k == kk)
    Xm <- cbind(1, impute(as.matrix(X[i, m$cols, with = FALSE]), 0))
    out[i, ] <- Xm %*% m$B
  }
  out
}

fit_base <- function(tr) t(sapply(seq_len(MAX_K), function(kk) {
  dl <- tr[k == kk, delta]; quantile(c(dl, -dl), QL, names = FALSE)
}))

pred_base <- function(B, k) B[k, , drop = FALSE]

fit_ar <- function(panel, max_date, spec) {
  lags <- sprintf("ar_l%d", 0:(AR_P - 1L))
  d <- origin_rows(panel, max_date, spec)[date + 7L <= max_date & !is.na(z_next) & !grepl(AUX_RE, location)]
  d <- d[complete.cases(d[, ..lags])]
  if (nrow(d) < 100) return(NULL)
  X <- cbind(1, as.matrix(d[, ..lags]))
  b <- qr.coef(qr(X), d$z_next); b[is.na(b)] <- 0
  r <- as.vector(d$z_next - X %*% b)
  s_pool <- sd(r)
  sl <- data.table(location = d$location, r = r)[, .(n = .N, v = mean(r^2)), by = location]
  sl[, sigma := sqrt((n * v + 20 * s_pool^2) / (n + 20))]
  list(b = b, sigma = setNames(sl$sigma, sl$location), s_pool = s_pool)
}

pred_ar <- function(m, tasks, nsim = AR_SIMS, seed = 11) {
  out <- matrix(NA_real_, nrow(tasks), length(QL))
  if (is.null(m)) return(out)
  set.seed(seed)
  L <- as.matrix(tasks[, sprintf("ar_l%d", 0:(AR_P - 1L)), with = FALSE])
  sig <- unname(m$sigma[tasks$location]); sig[is.na(sig)] <- m$s_pool
  for (i in which(complete.cases(L))) {
    lag <- matrix(L[i, ], nsim, AR_P, byrow = TRUE)
    for (s in seq_len(tasks$k[i])) {
      znew <- pmax(m$b[1] + lag %*% m$b[-1] + rnorm(nsim, 0, sig[i]), -tasks$mu[i])
      lag <- cbind(znew, lag[, -AR_P, drop = FALSE])
    }
    out[i, ] <- quantile(lag[, 1] - tasks$level[i], QL, names = FALSE)
  }
  out
}

TREND_PHI <- 0.8

trend_med <- function(d) {
  damp <- cumsum(TREND_PHI^seq_len(MAX_K))
  s <- d$tp_d1_w5_c1; s[!is.finite(s)] <- 0
  a <- d$tp_d1_w5_c0 - d$level; a[!is.finite(a)] <- 0
  a + s * damp[d$k]
}

trend_scale <- function(d, ref) { x <- d$noise / ref; x[!is.finite(x)] <- 1; pmin(pmax(x, 0.5), 2) }

trend_cap <- function(med, k, lim) pmin(pmax(med, lim[k, 1]), lim[k, 2])

fit_trend <- function(tr) {
  d <- tr[is_aux %in% 0L]
  ref <- median(d$noise[is.finite(d$noise) & d$noise > 0]); if (!is.finite(ref)) ref <- 0.05
  lim <- t(vapply(seq_len(MAX_K), function(kk) {
    x <- d$delta[d$k == kk]; if (length(x) < 30) x <- d$delta
    quantile(x, c(0.01, 0.99), na.rm = TRUE, names = FALSE) }, c(0, 0)))
  r <- (d$delta - trend_cap(trend_med(d), d$k, lim)) / trend_scale(d, ref)
  list(ref = ref, lim = lim, q = t(vapply(seq_len(MAX_K), function(kk) {
    x <- r[d$k == kk & is.finite(r)]; if (length(x) < 30) x <- r[is.finite(r)]
    quantile(x, QL, names = FALSE) }, QL)))
}

pred_trend <- function(m, tasks)
  sort_rows(trend_cap(trend_med(tasks), tasks$k, m$lim) + m$q[tasks$k, , drop = FALSE] * trend_scale(tasks, m$ref))

holdout_split <- function(n, frac = 0.2, seed = 5) { set.seed(seed); sample.int(n) > round(n * frac) }

resid_quant <- function(r, k, sc) {
   r <- r / sc
   t(vapply(seq_len(MAX_K), function(kk) { x <- r[k == kk & is.finite(r)]; if (length(x) < 30) x <- r[is.finite(r)]
      quantile(x, QL, names = FALSE) }, QL))
}

col_fill <- function(X, med) { for (j in seq_len(ncol(X))) { b <- !is.finite(X[, j]); if (any(b)) X[b, j] <- med[j] }; X }

cap_n <- function(d, n, seed) { if (nrow(d) > n) { set.seed(seed); d[sample(.N, n)] } else d }

fit_xt <- function(tr, cols, n_max = getOption("dod.qrf_rows", 150000), seed = 2) {
   d <- cap_n(tr, n_max, seed)
   ranger::ranger(x = impute(as.data.frame(d[, ..cols])), y = d$delta, num.trees = getOption("dod.qrf_trees", 300),
                  min.node.size = 30, mtry = min(12L, length(cols)), sample.fraction = 0.5, splitrule = "extratrees",
                  num.random.splits = 2, quantreg = TRUE, num.threads = nthreads(), seed = seed, verbose = FALSE)
}

KNN_COLS <- c("level", "tp_d2_w4_c1", "tp_d2_w4_c2", "tp_d2_w6_c1", "tp_d1_w3_c1", "rm_w4", "level_lag1", "level_lag2", "sin1", "cos1")

fit_knn <- function(tr, n_max = 60000, seed = 3) {
   lapply(seq_len(MAX_K), function(kk) {
      d <- cap_n(tr[k == kk], n_max, seed + kk)
      X <- as.matrix(d[, ..KNN_COLS]); mu <- colMeans(X, na.rm = TRUE); s <- apply(X, 2, sd, na.rm = TRUE); s[!is.finite(s) | s == 0] <- 1
      X <- col_fill(sweep(sweep(X, 2, mu), 2, s, `/`), rep(0, ncol(X)))
      list(X = X, y = d$delta, mu = mu, s = s)
   })
}

pred_knn <- function(m, tasks, K = 60) {
   out <- matrix(NA_real_, nrow(tasks), length(QL))
   for (kk in unique(tasks$k)) {
      i <- which(tasks$k == kk); mm <- m[[kk]]
      Z <- col_fill(sweep(sweep(as.matrix(tasks[i, KNN_COLS, with = FALSE]), 2, mm$mu), 2, mm$s, `/`), rep(0, length(KNN_COLS)))
      nn <- FNN::get.knnx(mm$X, Z, k = min(K, nrow(mm$X)))$nn.index
      out[i, ] <- t(apply(nn, 1, function(ix) quantile(mm$y[ix], QL, names = FALSE)))
   }
   out
}

fit_seasonal <- function(tr) { d <- tr[is_aux %in% 0L & !is.na(season_week)]; list(sw = d$season_week, k = d$k, y = d$delta) }

pred_seasonal <- function(m, tasks) {
   out <- matrix(NA_real_, nrow(tasks), length(QL))
   key <- unique(tasks[, .(k, season_week)])
   for (r in seq_len(nrow(key))) {
      i <- which(tasks$k == key$k[r] & tasks$season_week == key$season_week[r])
      for (w in c(2, 4, 8)) {
         dd <- abs(m$sw - key$season_week[r]); dd <- pmin(dd, 53 - dd)
         x <- m$y[m$k == key$k[r] & dd <= w]
         if (length(x) >= 100) break
      }
      if (length(x)) out[i, ] <- matrix(quantile(x, QL, names = FALSE), length(i), length(QL), byrow = TRUE)
   }
   out
}

growth_vars <- function(d) {
   cc <- 0.05 * d$p95^4 + 0.002
   ly <- function(z) log(from_z(z, d$p95, d$mu) + cc)
   l0 <- ly(d$level)
   data.table(g1 = l0 - ly(d$level_lag1), g2 = (l0 - ly(d$level_lag2)) / 2, dev = l0 - ly(d$rm_w4),
              sin1 = d$sin1, cos1 = d$cos1, l0 = l0, cc = cc)
}

fit_growthqr <- function(tr, n_max = 60000, seed = 4) {
   lapply(seq_len(MAX_K), function(kk) {
      d <- cap_n(tr[k == kk], n_max, seed + kk)
      g <- growth_vars(d); y <- log(from_z(d$z_target, d$p95, d$mu) + g$cc) - g$l0
      X <- as.matrix(g[, .(g1, g2, dev, sin1, cos1)]); ok <- complete.cases(X) & is.finite(y)
      X <- cbind(1, X[ok, , drop = FALSE]); y <- y[ok]
      if (nrow(X) < 50) return(NULL)
      sapply(QL, function(q) tryCatch(quantreg::rq.fit(X, y, tau = q, method = "fn")$coefficients,
                                      error = function(e) quantreg::rq.fit(X, y, tau = q, method = "br")$coefficients))
   })
}

pred_growthqr <- function(m, tasks) {
   out <- matrix(NA_real_, nrow(tasks), length(QL))
   g <- growth_vars(tasks); X <- cbind(1, as.matrix(g[, .(g1, g2, dev, sin1, cos1)]))
   for (kk in unique(tasks$k)) {
      B <- m[[kk]]; if (is.null(B)) next
      i <- which(tasks$k == kk & complete.cases(X))
      Lq <- X[i, , drop = FALSE] %*% B
      yq <- pmax(exp(g$l0[i] + Lq) - g$cc[i], 0)
      out[i, ] <- to_z(yq, tasks$p95[i], tasks$mu[i]) - tasks$level[i]
   }
   out
}

PT_COLS <- c("level", "tp_d2_w4_c1", "tp_d2_w4_c2", "tp_d2_w6_c1", "tp_d1_w3_c1", "rm_w4", "noise", "g_slope", "season_week")

fit_point <- function(tr, type, n_max = 60000, seed = 6) {
   d <- cap_n(tr, n_max, seed)
   cols <- intersect(PT_COLS, names(d))
   X <- as.matrix(d[, ..cols]); med <- apply(X, 2, median, na.rm = TRUE); med[!is.finite(med)] <- 0
   X <- col_fill(X, med); fit_rows <- holdout_split(nrow(d))
   ref <- median(d$noise[is.finite(d$noise) & d$noise > 0]); if (!is.finite(ref)) ref <- 0.05
   mu <- colMeans(X); s <- apply(X, 2, sd); s[!is.finite(s) | s == 0] <- 1
   Xs <- cbind(sweep(sweep(X, 2, mu), 2, s, `/`), k = (d$k - 3) / 2)
   set.seed(seed)
   fit <- switch(type,
      gam  = { df <- data.frame(X, k = factor(d$k), delta = d$delta)
               mgcv::bam(delta ~ k + s(level, k = 8) + s(tp_d2_w4_c1, k = 8) + s(tp_d2_w4_c2, k = 6) + s(rm_w4, k = 6) +
                            s(noise, k = 5) + s(g_slope, k = 5) + s(season_week, bs = "cc", k = 8) + s(tp_d2_w4_c1, by = k, k = 5),
                         data = df[fit_rows, ], discrete = TRUE, nthreads = nthreads()) },
      mars = earth::earth(x = Xs[fit_rows, ], y = d$delta[fit_rows], degree = 2, nk = 31),
      mlp  = nnet::nnet(x = Xs[fit_rows, ], y = d$delta[fit_rows], size = 8, linout = TRUE, decay = 1e-3, maxit = 300,
                        trace = FALSE, MaxNWts = 2000))
   m <- list(type = type, fit = fit, cols = cols, med = med, mu = mu, s = s, ref = ref)
   hold <- !fit_rows
   r <- d$delta[hold] - point_predict(m, X[hold, , drop = FALSE], d$k[hold])
   m$q <- resid_quant(r, d$k[hold], trend_scale(d[hold], ref))
   m
}

point_predict <- function(m, X, k) {
   Xs <- cbind(sweep(sweep(X, 2, m$mu), 2, m$s, `/`), k = (k - 3) / 2)
   as.numeric(switch(m$type,
      gam  = predict(m$fit, newdata = data.frame(X, k = factor(k, levels = 1:MAX_K))),
      mars = predict(m$fit, newdata = Xs),
      mlp  = predict(m$fit, newdata = Xs)))
}

pred_point <- function(m, tasks) {
   X <- col_fill(as.matrix(tasks[, m$cols, with = FALSE]), m$med)
   sort_rows(point_predict(m, X, tasks$k) + m$q[tasks$k, , drop = FALSE] * trend_scale(tasks, m$ref))
}

pred_series <- function(panel, tasks, method) {
   out <- matrix(NA_real_, nrow(tasks), length(QL))
   if (is.null(panel)) return(out)
   pairs <- unique(tasks[, .(location, date)])
   zq <- qnorm(pmin(pmax(QL, 1e-4), 1 - 1e-4))
   for (r in seq_len(nrow(pairs))) {
      h <- panel[location == pairs$location[r] & date <= pairs$date[r] & date > pairs$date[r] - 7L * 156L & !is.na(level), level]
      if (length(h) < 20) next
      fc <- tryCatch(suppressWarnings(switch(method,
         ets   = forecast::forecast(forecast::ets(ts(h), model = "AAN", damped = TRUE), h = MAX_K, level = 80),
         arima = forecast::forecast(forecast::Arima(ts(h), order = c(1, 1, 1)), h = MAX_K, level = 80),
         theta = forecast::thetaf(ts(h), h = MAX_K, level = 80))), error = function(e) NULL)
      if (is.null(fc)) next
      mn <- as.numeric(fc$mean); sdv <- pmax((as.numeric(fc$upper[, 1]) - mn) / qnorm(0.9), 1e-4)
      i <- which(tasks$location == pairs$location[r] & tasks$date == pairs$date[r])
      kk <- pmin(tasks$k[i], MAX_K)
      out[i, ] <- mn[kk] + outer(sdv[kk], zq) - tasks$level[i]
   }
   out
}

SERIES_MODELS <- c("ets", "arima", "theta")

antilag_apply <- function(Qz, tk, beta) {
   if (is.null(beta) || all(beta == 1)) return(Qz)
   Qz + (beta[pmin(tk$horizon, length(beta))] - 1) * Qz[, MED]
}

TREND_GROWTH <- 0.10

TREND_SIGNALS <- c("own", "counts", "case", "dhn", "ww", "nssp")

TREND_DETECTORS <- c(TREND_SIGNALS, "any", "any2", "majority")

roll4 <- function(d) {
   d <- d[!is.na(v)]; setorder(d, location, date)
   d[, `:=`(m = frollmean(v, 4), s = (-1.5 * shift(v, 3) - 0.5 * shift(v, 2) + 0.5 * shift(v, 1) + 1.5 * v) / 5,
            ok = as.integer(date - shift(date, 3)) == 21L), by = location]
   d[!(ok %in% TRUE), `:=`(m = NA_real_, s = NA_real_)]
   d[, ok := NULL][]
}

rising_rel <- function(d, floor) d[, .(location, date, up = m >= floor & s > TREND_GROWTH * pmax(m, floor))]

trend_table <- function(raw, dis, regions, parent_map = NULL, nssp = NULL) {
   spec <- DISEASE[[dis]]
   get_s <- function(col) if (col %in% names(raw)) raw[region %in% regions, .(location = region, date, v = get(col))] else NULL
   sig <- list()
   own <- get_s(spec$y)
   if (!is.null(own)) sig$own <- rising_rel(roll4(copy(own)), 0.02)
   x <- get_s(spec$enc);             if (!is.null(x)) sig$counts <- rising_rel(roll4(x), 3)
   x <- get_s(spec$cov[["case"]]);   if (!is.null(x)) sig$case <- rising_rel(roll4(x), 1)
   x <- get_s(spec$cov[["ww"]])
   if (!is.null(x)) { r <- roll4(x); sig$ww <- r[, .(location, date, up = s > TREND_GROWTH)] }
   if (!is.null(parent_map) && !is.null(sig$own)) {
      allown <- rising_rel(roll4(raw[, .(location = region, date, v = get(spec$y))]), 0.02)
      pm <- rbind(parent_map[, .(location, parent)], data.table(location = regions, parent = regions))
      pm <- unique(pm[location %in% regions], by = "location")
      sig$dhn <- merge(pm, allown[, .(parent = location, date, up)], by = "parent", allow.cartesian = TRUE)[, .(location, date, up)]
   }
   if (!is.null(nssp)) {
      map <- region_state_map(regions)
      st <- nssp[disease == dis & is_state == TRUE, .(state, date, y)]
      if (nrow(map) && nrow(st)) {
         x <- merge(map, st, by = "state", allow.cartesian = TRUE)[, .(v = sum(w * y) / sum(w)), by = .(location, date)]
         sig$nssp <- rising_rel(roll4(x), 0.05)
      }
   }
   out <- NULL
   for (nm in names(sig)) { s <- sig[[nm]][, .(location, date, up)]; setnames(s, "up", nm)
      out <- if (is.null(out)) s else merge(out, s, by = c("location", "date"), all = TRUE) }
   for (nm in setdiff(TREND_SIGNALS, names(out))) set(out, j = nm, value = NA)
   setkey(out, location, date)
   out
}

detector_flags <- function(fl) {
   S <- as.matrix(fl[, ..TREND_SIGNALS]); avail <- !is.na(S); S[!avail] <- FALSE
   n_up <- rowSums(S); n_av <- rowSums(avail)
   D <- cbind(S, any = n_up >= 1, any2 = n_up >= 2, majority = n_av > 0 & n_up > n_av / 2)
   storage.mode(D) <- "logical"; D[, TREND_DETECTORS, drop = FALSE]
}

trend_state_now <- function(raw, dis, locations, at, parent_map, nssp, detector) {
   tt <- trend_table(raw, dis, unique(locations), parent_map, nssp)
   D <- detector_flags(tt[J(locations, rep(as.IDate(at), length(locations)))])
   D[, detector] %in% TRUE
}

sort_rows <- function(Q) t(apply(Q, 1, sort))

widen_q   <- function(Q, c) { med <- Q[, MED]; med + c * (Q - med) }

fit_all <- function(tr, panel, max_date, spec, cols, which) {
  f <- list(); tm <- numeric(0)
  timed <- function(name, expr) { t0 <- Sys.time(); v <- expr
                                  tm[[name]] <<- as.numeric(difftime(Sys.time(), t0, units = "mins")); v }
  if ("gbqr" %in% which) f$gbqr <- timed("gbqr", fit_gbqr(tr, cols))
  if ("qrf"  %in% which) f$qrf  <- timed("qrf",  fit_qrf(tr, cols))
  if ("lqr"  %in% which) f$lqr  <- timed("lqr",  fit_lqr(tr, setdiff(LQR_COLS, spec$drop_feats)))
  if ("trend" %in% which) f$trend <- timed("trend", fit_trend(tr))
  if ("xt"    %in% which) f$xt    <- timed("xt",    fit_xt(tr, cols))
  if ("knn"   %in% which) f$knn   <- timed("knn",   fit_knn(tr))
  if ("seasonal" %in% which) f$seasonal <- timed("seasonal", fit_seasonal(tr))
  if ("growthqr" %in% which) f$growthqr <- timed("growthqr", fit_growthqr(tr))
  for (pm in intersect(c("gam", "mars", "mlp"), which)) f[[pm]] <- timed(pm, fit_point(tr, pm))
  for (sm in intersect(SERIES_MODELS, which)) f[[sm]] <- list(series = sm)
  if ("ar"   %in% which) f$ar   <- timed("ar",   list(m = fit_ar(panel, max_date, spec)))
  f$baseline <- fit_base(tr[is_aux %in% 0L])
  attr(f, "minutes") <- tm
  f
}

predict_all <- function(fits, tasks, cols, panel = NULL) {
  P <- list()
  if (!is.null(fits$gbqr)) P$gbqr <- sort_rows(pred_gbqr(fits$gbqr, as.matrix(tasks[, ..cols])))
  if (!is.null(fits$qrf))  P$qrf  <- sort_rows(pred_qrf(fits$qrf, tasks[, ..cols]))
  if (!is.null(fits$lqr))  P$lqr  <- sort_rows(pred_lqr(fits$lqr, tasks, tasks$k))
  if (!is.null(fits$trend)) P$trend <- pred_trend(fits$trend, tasks)
  if (!is.null(fits$xt))       P$xt       <- sort_rows(pred_qrf(fits$xt, tasks[, ..cols]))
  if (!is.null(fits$knn))      P$knn      <- pred_knn(fits$knn, tasks)
  if (!is.null(fits$seasonal)) P$seasonal <- pred_seasonal(fits$seasonal, tasks)
  if (!is.null(fits$growthqr)) P$growthqr <- sort_rows(pred_growthqr(fits$growthqr, tasks))
  for (pm in intersect(c("gam", "mars", "mlp"), names(fits))) P[[pm]] <- pred_point(fits[[pm]], tasks)
  for (sm in intersect(SERIES_MODELS, names(fits))) P[[sm]] <- sort_rows(pred_series(panel, tasks, sm))
  P$baseline <- pred_base(fits$baseline, tasks$k)
  if (!is.null(fits$ar)) P$ar <- pred_ar(fits$ar$m, tasks)
  for (m in setdiff(names(P), "baseline")) {
    na <- !complete.cases(P[[m]]); if (any(na)) P[[m]][na, ] <- P$baseline[na, , drop = FALSE]
  }
  P
}

combine_q <- function(P, members, how = "mean") {
  members <- intersect(members, names(P))
  Q <- if (how == "median" && length(members) > 2) apply(simplify2array(P[members]), c(1, 2), median)
       else Reduce(`+`, P[members]) / length(members)
  sort_rows(matrix(Q, ncol = length(QL)))
}

to_pct <- function(Q, tasks) pmin(from_z(tasks$level + Q, tasks$p95, tasks$mu), 100)

qcol <- function(l) which(abs(QL - l) < 1e-9)

interp_q <- function(Q, lv) {
  x <- qnorm(QL); xn <- qnorm(pmin(pmax(lv, 1e-4), 1 - 1e-4)); n <- length(x)
  t(apply(Q, 1, function(q) {
    v <- approx(x, q, xout = xn, rule = 2)$y
    lo <- xn < x[1]; hi <- xn > x[n]
    if (any(lo)) v[lo] <- q[1] + (q[2] - q[1]) / (x[2] - x[1]) * (xn[lo] - x[1])
    if (any(hi)) v[hi] <- q[n] + (q[n] - q[n - 1]) / (x[n] - x[n - 1]) * (xn[hi] - x[n])
    v
  }))
}

apply_recal <- function(Qz, tk, rc) {
  if (is.null(rc) || rc$type == "none") return(Qz)
  if (rc$type == "widen") return(widen_q(Qz, rc$c))
  out <- Qz
  for (h in unique(tk$horizon)) {
    i <- which(tk$horizon == h)
    out[i, ] <- interp_q(Qz[i, , drop = FALSE], rc$maps[min(h, nrow(rc$maps)), ])
  }
  sort_rows(out)
}

SIZE_LEVELS <- c("small", "medium", "large", "DHN")

region_buckets <- function(raw, regions, before) {
   sz <- data.table(location = regions)
   if ("mhs_tot_encounters" %in% names(raw)) {
      e <- raw[region %in% regions & date < before & date >= before - 364L,
               .(enc = mean(mhs_tot_encounters, na.rm = TRUE)), by = .(location = region)]
      sz <- merge(sz, e, by = "location", all.x = TRUE)
   } else sz[, enc := NA_real_]
   dh <- grepl("^DHN", sz$location)
   cuts <- if (sum(!dh & is.finite(sz$enc)) >= 3) quantile(sz$enc[!dh], c(1/3, 2/3), na.rm = TRUE) else c(Inf, Inf)
   sz[, size := fifelse(dh, "DHN", fifelse(!is.finite(enc) | enc <= cuts[1], "small",
                                           fifelse(enc <= cuts[2], "medium", "large")))]
   sz[]
}

selection_for <- function(dis, selection_tbl = NULL, maps_tbl = NULL) {
  s_all <- if (isTRUE(USE_SELECTION) && !is.null(selection_tbl)) selection_tbl[disease == dis] else data.table()
  has_b <- nrow(s_all) && "bucket" %in% names(s_all) && !all(is.na(s_all$bucket))
  m_all <- if (!is.null(maps_tbl) && nrow(maps_tbl)) maps_tbl[disease == dis] else data.table()
  one <- function(b) {
    sel <- list(data = if (isTRUE(AUGMENT_CIV)) "aug" else "dod", members = MODELS, combine = COMBINE,
                recal = switch(RECALIBRATE, widen = list(type = "widen", c = WIDEN[[dis]] %||% 1),
                               none = list(type = "none"), pit = list(type = "pit_missing")))
    s <- if (!nrow(s_all)) NULL else if (!has_b) s_all[1] else if (any(s_all$bucket == b)) s_all[bucket == b][1]
         else if (any(s_all$bucket == "medium")) s_all[bucket == "medium"][1] else s_all[1]
    if (!is.null(s)) {
      sel$data <- s$data; sel$combine <- s$combine
      sel$members <- intersect(strsplit(s$members, "+", fixed = TRUE)[[1]], MODELS)
      sel$recal <- list(type = s$recal, c = s$widen)
      if (sel$recal$type == "pit") {
        m <- if (!nrow(m_all)) m_all else if ("bucket" %in% names(m_all) && has_b) m_all[bucket == s$bucket] else m_all
        sel$recal <- if (nrow(m)) list(type = "pit", maps = as.matrix(dcast(m, horizon ~ level, value.var = "new_level")[, -1]))
                     else list(type = "pit_missing")
      }
    }
    if (identical(sel$recal$type, "pit_missing")) {
      sel$recal <- list(type = "none")
    }
    if (!length(sel$members)) sel$members <- MODELS
    if (sel$data == "alt" && is.null(DISEASE[[dis]]$alt)) sel$data <- "dod"
    sel
  }
  out <- list(by_bucket = lapply(setNames(nm = SIZE_LEVELS), one),
              approach = if (nrow(s_all) && "approach" %in% names(s_all)) s_all$approach[1] else "switches",
              tau = if (isTRUE(RECONCILE)) SHRINK_TAU else Inf,
              coherence = if (isTRUE(RECONCILE)) COHERENCE else "off")
  out$trend <- NULL
  if (isTRUE(TREND_AWARE) && nrow(s_all) && "trend_detector" %in% names(s_all) && !is.na(s_all$trend_detector[1]) &&
      nzchar(s_all$trend_detector[1])) {
    tr <- list(detector = s_all$trend_detector[1], method = s_all$trend_method[1])
    if (tr$method == "by_state") {
      mm <- function(b) { m <- if (nrow(m_all) && "bucket" %in% names(m_all)) m_all[bucket == b] else data.table()
                          if (nrow(m)) as.matrix(dcast(m, horizon ~ level, value.var = "new_level")[, -1]) else NULL }
      tr$maps_rising <- mm("trend_rising"); tr$maps_other <- mm("trend_other")
      if (is.null(tr$maps_rising) || is.null(tr$maps_other)) tr <- NULL
    }
    out$trend <- tr
  }
  bcols <- paste0("antilag_b", horizons)
  out$antilag <- if (isTRUE(ANTILAG) && nrow(s_all) && all(bcols %in% names(s_all)) && all(is.finite(unlist(s_all[1, ..bcols]))))
                    as.numeric(unlist(s_all[1, ..bcols])) else NULL
  if (isTRUE(RECONCILE) && nrow(s_all) && all(c("recon_tau", "recon_coherence") %in% names(s_all))) {
    out$tau <- if (is.na(s_all$recon_tau[1])) Inf else as.numeric(s_all$recon_tau[1])
    out$coherence <- if (is.na(s_all$recon_coherence[1])) "off" else s_all$recon_coherence[1]
  }
  out
}

recon_groups <- function(parent_map, regions) {
   if (is.null(parent_map) || !"pure" %in% names(parent_map)) return(list())
   pm <- parent_map[pure == TRUE & location %in% regions & parent %in% regions]
   if (!nrow(pm)) return(list())
   split(pm$location, pm$parent)
}

group_stats <- function(raw, spec, groups, o, window = RECON_WINDOW) {
   if (!"mhs_tot_encounters" %in% names(raw) || !length(groups)) return(list())
   has_enc <- spec$enc %in% names(raw)
   w <- raw[date <= o & date > o - 7L * window & region %in% c(names(groups), unlist(groups))]
   w <- w[, .(region, date, tot = mhs_tot_encounters, pct = get(spec$y),
              enc = if (has_enc) get(spec$enc) else get(spec$y) * mhs_tot_encounters / 100)]
   out <- list()
   for (d in names(groups)) {
      wd <- w[region == d & is.finite(tot) & tot > 0]
      Tr <- w[region %in% groups[[d]], .(T = mean(tot, na.rm = TRUE), E = sum(enc, na.rm = TRUE),
                                          Ts = sum(tot[is.finite(enc)], na.rm = TRUE)), by = region][is.finite(T) & T > 0]
      if (nrow(wd) < 2 || !nrow(Tr)) next
      Td <- mean(wd$tot)
      cover <- sum(Tr$T) / Td
      if (cover > 1.05) next
      sums <- w[region %in% Tr$region, .(E = sum(enc), T = sum(tot), n = .N), by = date]
      rest <- merge(wd[, .(date, Ed = enc, Td = tot, pd = pct)], sums[n == nrow(Tr)], by = "date")
      rest[, `:=`(T0 = Td - T, p0 = 100 * (Ed - E) / (Td - T))]
      ratio <- rest[T0 > 0.01 * Td & is.finite(pd) & pd > 0 & is.finite(p0), pmax(p0, 0) / pd]
      pd_pool <- sum(wd$enc, na.rm = TRUE) / sum(wd$tot[is.finite(wd$enc)])
      q <- if (is.finite(pd_pool) && pd_pool > 0) pmin(pmax((Tr$E / pmax(Tr$Ts, 1)) / pd_pool, 0.1), 10) else rep(1, nrow(Tr))
      out[[d]] <- list(d = d, children = Tr$region, w = setNames(Tr$T / Td, Tr$region), q = setNames(q, Tr$region),
                       w0 = if (1 - cover >= 0.02) 1 - cover else 0, cover = cover,
                       T = c(setNames(Td, d), setNames(Tr$T, Tr$region)), T0 = max(Td - sum(Tr$T), 1),
                       rho = if (length(ratio) >= 2) min(median(ratio), 5) else 1,
                       rho_sd = if (length(ratio) >= 2) sd(ratio) else 0.5)
   }
   out
}

shrink_deltas <- function(Y, keys, raw, dis, groups, tau = SHRINK_TAU, window = RECON_WINDOW) {
   delta <- numeric(nrow(Y))
   if (!length(groups) || !is.finite(tau)) return(list(delta = delta, info = NULL))
   med <- Y[, MED]
   k <- data.table(origin = as.IDate(keys$origin), horizon = as.integer(keys$horizon), location = keys$location,
                   row = seq_len(nrow(Y)))
   setkey(k, origin, horizon)
   info <- list(); oo <- unique(k$origin)
   for (j in seq_along(oo)) {
      o <- oo[j]
      for (g in group_stats(raw, DISEASE[[dis]], groups, o, window)) for (h in unique(k[.(o)]$horizon)) {
         kk <- k[.(o, h)]
         i_d <- kk[location == g$d, row]; kc <- kk[location %in% g$children]
         if (length(i_d) != 1 || !nrow(kc)) next
         m   <- med[kc$row]
         syn <- unname(g$q[kc$location]) * med[i_d]
         psi <- pmax(m, 1e-3) * (100 - pmin(m, 99.9)) / pmax(unname(g$T[kc$location]), 1)
         kap <- psi / (psi + (tau * pmax(syn, 0.01))^2)
         delta[kc$row] <- kap * (syn - m)
         info[[length(info) + 1L]] <- data.table(origin = o, horizon = h, dhn = g$d, location = kc$location,
                                                 weekly_encounters = round(unname(g$T[kc$location])), pull = kap)
      }
   }
   list(delta = delta, info = rbindlist(info))
}

recon_deltas <- function(Y, keys, raw, dis, groups, weights = "size", window = RECON_WINDOW) {
   delta <- numeric(nrow(Y))
   if (!length(groups)) return(list(delta = delta, info = NULL))
   spec <- DISEASE[[dis]]
   med <- Y[, MED]
   sdv <- pmax((Y[, qcol(0.75)] - Y[, qcol(0.25)]) / 1.349, 1e-4)
   k <- data.table(origin = as.IDate(keys$origin), horizon = as.integer(keys$horizon), location = keys$location,
                   row = seq_len(nrow(Y)))
   setkey(k, origin, horizon)
   info <- list()
   oo <- unique(k$origin)
   for (j in seq_along(oo)) {
      o <- oo[j]
      for (g in group_stats(raw, spec, groups, o, window)) for (h in unique(k[.(o)]$horizon)) {
         kk <- k[.(o, h)]
         i_d <- kk[location == g$d, row]
         kc  <- kk[location %in% g$children]
         if (length(i_d) != 1 || !nrow(kc)) next
         rows <- c(i_d, kc$row)
         m  <- med[rows]
         Tn <- c(g$T[[g$d]], g$T[kc$location])
         wv <- unname(g$w[kc$location])
         vb <- pmax(m, 1e-3) * (100 - pmin(m, 99.9)) / pmax(Tn, 1)
         v  <- if (weights == "spread") sdv[rows]^2 else {
            c_rel <- median(pmax(sdv[rows]^2 - vb, 0) / pmax(m, 0.01)^2)
            c_rel * pmax(m, 0.01)^2 + vb }
         m0 <- g$rho * m[1]
         v0 <- if (g$w0 > 0) g$rho^2 * v[1] + (g$rho_sd * m[1])^2 + pmax(m0, 1e-3) * (100 - pmin(m0, 99.9)) / g$T0 else 0
         e  <- m[1] - sum(wv * m[-1]) - g$w0 * m0
         S  <- v[1] + sum(wv^2 * v[-1]) + g$w0^2 * v0
         delta[rows] <- e / S * c(-v[1], wv * v[-1])
         info[[length(info) + 1L]] <- data.table(origin = o, horizon = h, dhn = g$d, n_regions = nrow(kc),
                                                 share_covered = g$cover, gap_before = e)
      }
   }
   list(delta = delta, info = rbindlist(info))
}

apply_recon <- function(Y, delta, lambda) {
   if (lambda == 0 || all(delta == 0)) return(Y)
   m  <- Y[, MED]
   nm <- pmax(m + lambda * delta, 0)
   i  <- which(delta != 0)
   big <- i[m[i] > 1e-4]; small <- setdiff(i, big)
   if (length(big))   Y[big, ]   <- Y[big, , drop = FALSE] * pmin(pmax(nm[big] / m[big], 0.25), 4)
   if (length(small)) Y[small, ] <- pmax(Y[small, , drop = FALSE] + lambda * delta[small], 0)
   pmin(Y, 100)
}

reconcile_all <- function(Y, keys, raw, dis, groups, tau = SHRINK_TAU, coherence = COHERENCE) {
   s1 <- shrink_deltas(Y, keys, raw, dis, groups, tau)
   Y1 <- apply_recon(Y, s1$delta, 1)
   if (coherence == "off") return(list(Y = Y1, shrink = s1$info, coherence = NULL))
   s2 <- recon_deltas(Y1, keys, raw, dis, groups, coherence)
   list(Y = apply_recon(Y1, s2$delta, 1), shrink = s1$info, coherence = s2$info)
}

keep_min_obs <- function(df, n = 12L) df[location %in% df[!is.na(y), .N, by = location][N >= n, location]]

disease_frame <- function(raw, spec, dis, nssp = NULL, aug = FALSE, min_obs = 12L) {
  clamp <- function(v) pmin(pmax(v, 0), 100)
  df <- raw[!is.na(get(spec$y)), .(location = region, date, y = clamp(get(spec$y)))]
  if (aug) {
    civ <- spec$cov[["civpct"]]
    if (civ %in% names(raw)) df <- rbind(df, raw[!is.na(get(civ)), .(location = paste0("civ:", region), date, y = clamp(get(civ)))])
    if (!is.null(nssp)) df <- rbind(df, nssp[disease == dis, .(location, date, y = clamp(y))])
  }
  keep_min_obs(unique(df, by = c("location", "date")), min_obs)
}

make_tasks <- function(panel, ref_end, regions) {
  last <- panel[location %in% regions & !is.na(z) & !is.na(tp_d2_w6_c0)][, .SD[which.max(date)], by = location]
  tasks <- rbindlist(lapply(horizons, function(h) copy(last)[, `:=`(horizon = h, target_end_date = ref_end + 7L * h)]))
  tasks[, k := as.integer(target_end_date - date) %/% 7L]
  tasks[k > MAX_K, k := MAX_K]
  add_fourier(tasks)
  setorder(tasks, location, horizon)
  tasks[]
}

q_long <- function(tasks, Q, model, dis) {
  data.table(disease = dis, model = model, location = rep(tasks$location, times = length(QL)),
             horizon = rep(tasks$horizon, times = length(QL)),
             target_end_date = rep(tasks$target_end_date, times = length(QL)),
             quantile = rep(QL, each = nrow(tasks)), value = as.vector(Q))
}

forecast_disease <- function(dis, raw, ref_end, regions, parent_map, nssp, selection_tbl = NULL, maps_tbl = NULL,
                             buckets = NULL) {
  spec0 <- DISEASE[[dis]]
  if (!spec0$y %in% names(raw)) return(NULL)
  sb <- selection_for(dis, selection_tbl, maps_tbl)
  if (is.null(buckets)) buckets <- region_buckets(raw, regions, ref_end + 1L)
  bmap <- setNames(as.character(buckets$size), buckets$location)
  cutoff <- ref_end + 1L
  settings <- unique(vapply(sb$by_bucket, `[[`, "", "data"))
  fitted <- list()
  for (st in settings) {
    spec <- spec_for(spec0, st)
    mem <- unique(unlist(lapply(Filter(function(x) x$data == st, sb$by_bucket), `[[`, "members")))
    df <- disease_frame(raw, spec, dis, nssp, aug = st == "aug")
    st_stats <- transform_stats(df, cutoff)
    panel <- build_features(df, raw, st_stats, spec, dis, cutoff, parent_map, nssp)
    cols <- model_cols(panel, spec)
    tr <- cap_rows(make_training_rows(panel, ref_end, spec))

    fits <- fit_all(tr, panel, ref_end, spec, cols, mem)
    tasks_st <- make_tasks(panel, ref_end, regions)
    fitted[[st]] <- list(tasks = tasks_st, P = predict_all(fits, tasks_st, cols, panel))
  }
  main <- names(sort(table(vapply(sb$by_bucket, `[[`, "", "data")), decreasing = TRUE))[1]
  tasks <- copy(fitted[[main]]$tasks)
  tasks[, size := unname(bmap[location])][is.na(size), size := "medium"]
  Qens <- matrix(NA_real_, nrow(tasks), length(QL)); Q0 <- Qens
  for (b in unique(tasks$size)) {
    s <- sb$by_bucket[[b]]
    i <- which(tasks$size == b)
    Fs <- fitted[[s$data]]
    j <- match(paste(tasks$location[i], tasks$horizon[i]), paste(Fs$tasks$location, Fs$tasks$horizon))
    Pb <- lapply(Fs$P, function(Q) Q[j, , drop = FALSE])
    Q0[i, ] <- combine_q(Pb, s$members, s$combine)
    Qens[i, ] <- apply_recal(Q0[i, , drop = FALSE], tasks[i], s$recal)
  }
  if (!is.null(sb$trend)) {
    st <- trend_state_now(raw, dis, tasks$location, ref_end, parent_map, nssp, sb$trend$detector)
    if (sb$trend$method == "switch") { if (any(st)) Qens[st, ] <- Q0[st, , drop = FALSE] } else {
      if (any(st))  Qens[st, ]  <- apply_recal(Q0[st, , drop = FALSE],  tasks[st],  list(type = "pit", maps = sb$trend$maps_rising))
      if (any(!st)) Qens[!st, ] <- apply_recal(Q0[!st, , drop = FALSE], tasks[!st], list(type = "pit", maps = sb$trend$maps_other)) }
  } else if (!is.null(sb$antilag)) {
    Qens <- antilag_apply(Qens, tasks, sb$antilag)
  }
  P <- fitted[[main]]$P
  P$ensemble <- Qens
  out <- rbindlist(lapply(names(P), function(m) q_long(tasks, to_pct(P[[m]], tasks), m, dis)))
  groups <- recon_groups(parent_map, regions)
  if ((is.finite(sb$tau) || sb$coherence != "off") && length(groups)) {
    rc <- reconcile_all(to_pct(P$ensemble, tasks), tasks[, .(origin = ref_end, location, horizon)],
                        raw, dis, groups, sb$tau, sb$coherence)
    out[model == "ensemble", model := "ensemble_unrec"]
    out <- rbind(out, q_long(tasks, rc$Y, "ensemble", dis))
  }

  out
}

sel_file  <- file.path(path_backtest, "selection.csv")
map_file  <- file.path(path_backtest, "recal_map.csv")
size_file <- file.path(path_backtest, "size_buckets.csv")
saved_sel <- if (file.exists(sel_file)) fread(sel_file) else NULL
bt_ok     <- names(USE_BACKTEST_SETTINGS)[USE_BACKTEST_SETTINGS]
from_bt   <- if (is.null(saved_sel)) data.table() else saved_sel[disease %in% intersect(DISEASES, bt_ok)]
no_bt     <- setdiff(DISEASES, from_bt$disease)
selection_tbl <- rbind(from_bt, DEFAULT_SETTINGS[disease %in% no_bt], fill = TRUE)
maps_tbl  <- if (file.exists(map_file) && nrow(from_bt)) fread(map_file)[disease %in% from_bt$disease] else NULL
size_tbl  <- if (file.exists(size_file)) fread(size_file) else NULL

fc <- rbindlist(lapply(DISEASES, forecast_disease, raw = raw, ref_end = latest_week, regions = forecast_regions,
                       parent_map = parent_map, nssp = nssp, selection_tbl = selection_tbl, maps_tbl = maps_tbl,
                       buckets = size_tbl))

band_table <- function(fc, mdl = "ensemble") {
   e <- fc[model == mdl]
   e[, qc := sprintf("q%03d", round(quantile * 1000))]
   dcast(e, disease + location + horizon + target_end_date ~ qc, value.var = "value")
}

make_overview_plots <- function(raw, fc, ref_end, per_page = 12, history_weeks = 30) {
   W <- band_table(fc); out <- list()
   for (dz in unique(W$disease)) {
      locs  <- sort(unique(W[disease == dz, location]))
      pages <- split(locs, ceiling(seq_along(locs) / per_page))
      for (pg in seq_along(pages)) {
         ch  <- pages[[pg]]
         obs <- raw[region %in% ch & date > ref_end - 7L * history_weeks,
                    .(location = region, date, y = get(DISEASE[[dz]]$y))][!is.na(y)]
         f   <- W[disease == dz & location %in% ch]
         out[[sprintf("%s_page%d", dz, pg)]] <- ggplot() +
            geom_ribbon(data = f, aes(target_end_date, ymin = q025, ymax = q975), fill = "#457B9D", alpha = 0.15) +
            geom_ribbon(data = f, aes(target_end_date, ymin = q250, ymax = q750), fill = "#457B9D", alpha = 0.35) +
            geom_line(data = f, aes(target_end_date, q500), colour = "#1D3557", linetype = "dashed") +
            geom_point(data = f, aes(target_end_date, q500), colour = "#1D3557", size = 1) +
            geom_line(data = obs, aes(date, y)) + geom_point(data = obs, aes(date, y), size = 0.6) +
            geom_vline(xintercept = ref_end, linewidth = 0.3) +
            facet_wrap(~location, scales = "free_y", ncol = 4) +
            labs(title = sprintf("%s: %% of MHS outpatient encounters  (page %d of %d)", DISEASE[[dz]]$name, pg, length(pages)),
                 subtitle = sprintf("Data through %s (%s). Ensemble median, 50%% and 95%% intervals", ref_end, week_tag(ref_end)),
                 x = NULL, y = "%") +
            theme_minimal(base_size = 9) + theme(panel.grid.minor = element_blank())
      }
   }
   out
}

make_focus_plot <- function(raw, fc, ref_end, reg, dz, history_weeks = 52) {
   f   <- band_table(fc[disease == dz & location == reg])
   mem <- fc[disease == dz & location == reg & abs(quantile - 0.5) < 1e-9 & model != "ensemble"]
   obs <- raw[region == reg & date > ref_end - 7L * history_weeks, .(date, y = get(DISEASE[[dz]]$y))][!is.na(y)]
   ggplot() +
      geom_ribbon(data = f, aes(target_end_date, ymin = q025, ymax = q975), fill = "#457B9D", alpha = 0.15) +
      geom_ribbon(data = f, aes(target_end_date, ymin = q250, ymax = q750), fill = "#457B9D", alpha = 0.35) +
      geom_line(data = mem, aes(target_end_date, value, colour = model), linewidth = 0.5) +
      geom_line(data = f, aes(target_end_date, q500, colour = "ensemble"), linewidth = 1.1, linetype = "dashed") +
      geom_point(data = f, aes(target_end_date, q500, colour = "ensemble"), size = 2) +
      geom_line(data = obs, aes(date, y)) + geom_point(data = obs, aes(date, y), size = 1.2) +
      geom_vline(xintercept = ref_end, linewidth = 0.5) +
      scale_colour_manual(values = c(ensemble = "#1D3557", ensemble_unrec = "#8D99AE", gbqr = "#E63946", qrf = "#F4A261",
                                     lqr = "#2A9D8F", xt = "#8338EC", knn = "#3A86FF", mlp = "#FB5607", ar = "#9B5DE5",
                                     trend = "#E9C46A", seasonal = "#606C38", growthqr = "#BC6C25", gam = "#FF006E",
                                     mars = "#06D6A0", ets = "#7F5539", arima = "#B5838D", theta = "#6D6875",
                                     baseline = "grey50")) +
      labs(title = sprintf("%s, %s", reg, DISEASE[[dz]]$name),
           subtitle = sprintf("Data through %s; ensemble with 50%% / 95%% intervals and each member's median", ref_end),
           x = "Week ending", y = "% of outpatient encounters", colour = NULL) +
      theme_minimal() + theme(legend.position = "bottom", panel.grid.minor = element_blank())
}

plots_overview <- make_overview_plots(raw, fc, latest_week)
for (p in plots_overview) print(p)

if (is.null(focus_regions)) focus_regions <- head(forecast_regions, 3)
plots_focus <- list()
for (reg in intersect(focus_regions, unique(fc$location))) for (dz in DISEASES) {
   plots_focus[[paste(reg, dz)]] <- make_focus_plot(raw, fc, latest_week, reg, dz)
}

Q_COLS <- c("region", "epiweek", "year", "date", "target", "variable", "model", "quantile", "value")

P_COLS <- c(Q_COLS, "llim", "ulim")

make_outputs <- function(fc) {
  e <- fc[model == "ensemble"]
  w <- mmwr_of(e$target_end_date)
  e[, `:=`(region = location, epiweek = w$week, year = w$year, date = mdy_str(target_end_date),
           target = sprintf("%d wk ahead", horizon), variable = unname(vapply(DISEASE[disease], `[[`, "", "y")),
           model = MODEL_LABEL, value = round(pmin(pmax(value, 0), 100), value_digits))]
  q <- e[, ..Q_COLS]
  setorder(q, region, variable, quantile, target)
  lim <- function(l) e[abs(quantile - l) < 1e-9, .(region, variable, target, v = value)]
  p <- e[abs(quantile - 0.5) < 1e-9, .(region, epiweek, year, date, target, variable, model, quantile = "Point", value)]
  p <- merge(p, setnames(lim(point_interval[1]), "v", "llim"), by = c("region", "variable", "target"))
  p <- merge(p, setnames(lim(point_interval[2]), "v", "ulim"), by = c("region", "variable", "target"))
  setcolorder(p, P_COLS)
  setorder(p, region, variable, target)
  list(quantile = q, point = p)
}

validate_outputs <- function(out, ref_end) {
  q <- out$quantile; p <- out$point; bad <- character()
  if (!identical(names(q), Q_COLS)) bad <- c(bad, "quantile file columns differ from the example")
  if (!identical(names(p), P_COLS)) bad <- c(bad, "point file columns differ from the example")
  if (anyNA(q) || anyNA(p)) bad <- c(bad, "missing values")
  if (any(q$value < 0 | q$value > 100) || any(p$value < 0 | p$value > 100)) bad <- c(bad, "values outside [0, 100]")
  if (!all(q$target %in% sprintf("%d wk ahead", 1:4))) bad <- c(bad, "unexpected target labels")
  if (!all(c(q$variable, p$variable) %in% vapply(DISEASE, `[[`, "", "y"))) bad <- c(bad, "unexpected variable names")
  lv <- q[, .(n = .N, ok = setequal(round(quantile, 3), QL), mono = all(diff(value[order(quantile)]) >= -1e-9)),
          by = .(region, variable, target)]
  if (any(lv$n != length(QL)) || !all(lv$ok)) bad <- c(bad, "some region/variable/target lacks the 23 quantiles")
  if (!all(lv$mono)) bad <- c(bad, "quantiles not increasing")
  d <- as.IDate(q$date, format = "%m/%d/%Y")
  h <- as.integer(substr(q$target, 1, 1))
  if (anyNA(d) || any(d != ref_end + 7L * h)) bad <- c(bad, "date does not match target week")
  w <- mmwr_of(d)
  if (any(w$week != q$epiweek | w$year != q$year)) bad <- c(bad, "epiweek/year do not match date")
  if (nrow(p) != nrow(lv)) bad <- c(bad, "point rows missing")
  if (any(p$llim > p$value + 1e-9 | p$value > p$ulim + 1e-9)) bad <- c(bad, "point outside llim-ulim")
  med <- merge(p[, .(region, variable, target, value)], q[abs(quantile - 0.5) < 1e-9, .(region, variable, target, m = value)],
               by = c("region", "variable", "target"))
  if (any(abs(med$value - med$m) > 1e-9)) bad <- c(bad, "point value differs from the 0.5 quantile")
  if (length(bad)) stop("Forecast file check failed: ", paste(unique(bad), collapse = "; "), call. = FALSE)

  invisible(TRUE)
}

out_file <- function(kind, ref_end) file.path(output_dir, sprintf("%s-forecast_%s_regions_%s%s.csv",
                                    week_tag(ref_end), kind, dmy_tag(ref_end), file_suffix))

check_names <- function() {
  for (x in c(team_abbr, model_abbr)) if (!grepl("^[A-Za-z0-9]{1,14}$", x))
    stop("team_abbr and model_abbr must be 1-14 letters/digits (no hyphens, spaces or underscores): '", x, "'", call. = FALSE)
  if (nchar(team_name) >= 50 || nchar(model_name) >= 50) stop("team_name and model_name must be under 50 characters.", call. = FALSE)
  if (nchar(METHODS_TXT) >= 200) stop("METHODS_TXT must be under 200 characters.", call. = FALSE)
}

write_metadata <- function(dir = output_dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  fn <- file.path(dir, sprintf("metadata-%s-%s.txt", team_abbr, model_abbr))
  if (file.exists(fn)) return(invisible(fn))
  q <- function(x) sprintf('"%s"', gsub('"', "'", x))
  writeLines(c(
    sprintf("team_name: %s", q(team_name)),
    sprintf("model_name: %s", q(model_name)),
    sprintf("model_abbr: %s", q(paste0(team_abbr, "-", model_abbr))),
    sprintf("model_contributors: %s", q(contributors)),
    sprintf("website_url: %s", q(website_url)),
    sprintf("license: %s", q(license_txt)),
    sprintf("team_model_designation: %s", q(designation)),
    sprintf("methods: %s", q(METHODS_TXT)),
    "ensemble_of_hub_models: false"), fn)

  invisible(fn)
}

check_names()
dod_files <- make_outputs(fc)
validate_outputs(dod_files, latest_week)
forecast_date <- latest_week + 9L

q_rows   <- copy(dod_files$quantile)[, `:=`(quantile = as.character(quantile), llim = NA_real_, ulim = NA_real_)]
combined <- rbind(dod_files$point, q_rows, use.names = TRUE)
combined[, ord := fifelse(quantile == "Point", -1, suppressWarnings(as.numeric(quantile)))]
setorder(combined, region, variable, target, ord)
combined[, ord := NULL]
stopifnot(nrow(combined) == nrow(dod_files$point) + nrow(dod_files$quantile),
          identical(names(combined), P_COLS),
          combined[, .N, by = .(region, variable, target)][, all(N == length(QL) + 1)])

file_one      <- file.path(submit_dir, sprintf("%s-%s-%s%s.csv", format(forecast_date), team_abbr, model_abbr, file_suffix))
file_quantile <- file.path(submit_dir, basename(out_file("quantile", latest_week)))
file_point    <- file.path(submit_dir, basename(out_file("point", latest_week)))

if (SAVE_SUBMISSION) {
   dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
   dir.create(submit_dir, recursive = TRUE, showWarnings = FALSE)
   if (ONE_FILE) {
      fwrite(combined, file_one, eol = "\r\n")
   } else {
      fwrite(dod_files$quantile, file_quantile, eol = "\r\n")
      fwrite(dod_files$point,    file_point,    eol = "\r\n")
   }
   write_metadata(submit_dir)
   if (SAVE_PLOTS) {
      dir.create(file.path(output_dir, "plots"), showWarnings = FALSE)
      plot_file <- file.path(output_dir, "plots", sprintf("%s-forecast-plots.pdf", week_tag(latest_week)))
      pdf(plot_file, width = 11, height = 8.5)
      for (p in c(plots_overview, plots_focus)) print(p)
      invisible(dev.off())
   }
}
