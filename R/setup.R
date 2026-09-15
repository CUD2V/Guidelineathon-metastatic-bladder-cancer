# ===========================================================================
# setup.R  —  derived config objects (do not edit)
# ===========================================================================
# Validates the CONFIG block in run.R and builds the paths + executionSettings
# object the numbered steps rely on. Sourced by run.R at global scope.
# ===========================================================================

if (is.null(connectionDetails))
  stop("Define `connectionDetails` in run.R's CONFIG block (or site_config.R) ",
       "before running.", call. = FALSE)

# --- validate all required settings up-front --------------------------------
# Catch missing/NULL/empty settings before the pipeline is 30 minutes in.
.requiredStr <- c("databaseId", "cdmDatabaseSchema", "workDatabaseSchema",
                  "cohortTable", "labCohortTable", "rawLabResultsTable",
                  "covariateCohortTable", "artemisCohortName",
                  "episodeTable", "regimenClassTable", "outputFolder")
.requiredInt <- c("minCellCount", "labWindowBeforeDays", "labWindowAfterDays",
                  "conditionFlagWindowBeforeDays", "conditionFlagWindowAfterDays",
                  "bodyMeasurementsWindowDays")

.missing <- character(0)
for (.s in .requiredStr) {
  v <- settings[[.s]]
  if (is.null(v) || !nzchar(v))
    .missing <- c(.missing, paste0("  ", .s, " — must be a non-empty string"))
}
for (.s in .requiredInt) {
  v <- settings[[.s]]
  if (is.null(v) || !is.numeric(v))
    .missing <- c(.missing, paste0("  ", .s, " — must be a number (integer)"))
}
if (length(.missing) > 0L)
  stop("site_config.R / CONFIG block: the following settings are missing or invalid:\n",
       paste(.missing, collapse = "\n"), "\n\nSee site_config_template.R for reference.",
       call. = FALSE)

# BigQuery: sqlRenderTempEmulationSchema must be set (no real temp tables)
.dbms <- tryCatch(connectionDetails$dbms, error = function(e) NULL) %||%
         tryCatch(connectionDetails@dbms, error = function(e) NULL)
if (identical(.dbms, "bigquery")) {
  .tempSchema <- getOption("sqlRenderTempEmulationSchema")
  if (is.null(.tempSchema) || !nzchar(.tempSchema))
    stop("BigQuery requires options(sqlRenderTempEmulationSchema = ...) to be set.\n",
         "Add it to site_config.R — see site_config_template.R for reference.",
         call. = FALSE)
}

message("Config validated: databaseId = \"", settings$databaseId, "\", ",
        "cdm = ", settings$cdmDatabaseSchema, ", work = ", settings$workDatabaseSchema)
rm(.requiredStr, .requiredInt, .missing, .s, .dbms)

if (!nzchar(settings$vocabDatabaseSchema))
  settings$vocabDatabaseSchema <- settings$cdmDatabaseSchema

# default the endocrine-therapy strip ON for site configs predating the option
if (is.null(settings$stripEndocrineTherapy))
  settings$stripEndocrineTherapy <- TRUE

# default the validDrugs restriction for configs predating the options:
# regimen-component filter ON, ATC filter OFF (see run.R for why)
if (is.null(settings$validDrugsRegimenComponents))
  settings$validDrugsRegimenComponents <- TRUE
if (is.null(settings$validDrugsAtcClasses))
  settings$validDrugsAtcClasses <- character(0)

# default the age/sex strata columns ON (all three) for configs predating
# the option -- character(0) (all strata off) is a deliberate site choice,
# not a missing setting, so only NULL (the field doesn't exist at all) gets
# defaulted here.
if (is.null(settings$strataColumns))
  settings$strataColumns <- c("age_group", "sex", "age_sex")

projectRoot <- normalizePath(".", mustWork = FALSE)
sqlDir      <- file.path(projectRoot, "sql")
cohortsDir  <- file.path(projectRoot, "cohorts")
extrasDir   <- file.path(cohortsDir, "extras")
dir.create(settings$outputFolder, recursive = TRUE, showWarnings = FALSE)

# Resumable-state checkpoints (saveState()/loadState(), R/helpers.R) hold
# patient-level intermediates (ARTEMIS episodes/alignments, drug exposures) --
# unlike outputFolder's CSVs/zips, which are aggregate and privacy-censored,
# these are never meant to be shared, so they live in a separate .cache/
# folder rather than inside the output folder a site would zip up. Keyed by
# outputFolder's own name so a fresh outputFolder (e.g. a "clean" re-run)
# never silently resumes from a previous run's cached state.
if (is.null(settings$stateFolder))
  settings$stateFolder <- file.path(".cache", basename(settings$outputFolder))
dir.create(settings$stateFolder, recursive = TRUE, showWarnings = FALSE)

# One README.md per results/eligibility/<category>/ subfolder, excerpted
# verbatim from this repo's own README.md (writeCategoryReadmes(), R/helpers.R)
# -- written once up front so the folders are self-documenting even before
# any step writes a CSV into them.
writeCategoryReadmes()

# executionSettings object compatible with the vendored runArtemis()
# (it reads cdm/vocab/work schema, cohortTable, connectionDetails, artemisSettings
#  and checks class "OsmExecutionSettings").
artemisSettings <- structure(
  list(cohortTable = settings$cohortTable, episodeTable = settings$episodeTable),
  class = "OsmArtemisSettings"
)
executionSettings <- structure(
  list(
    connectionDetails   = connectionDetails,
    cdmDatabaseSchema   = settings$cdmDatabaseSchema,
    vocabDatabaseSchema = settings$vocabDatabaseSchema,
    workDatabaseSchema  = settings$workDatabaseSchema,
    cohortTable         = settings$cohortTable,
    databaseId          = settings$databaseId,
    minCellCount        = settings$minCellCount,
    artemisSettings     = artemisSettings
  ),
  class = "OsmExecutionSettings"
)
