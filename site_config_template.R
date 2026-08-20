# site_config_template.R — copy to site_config.R and fill in your values
#
# site_config.R is gitignored so your credentials and project-specific
# settings stay out of version control. The run scripts (run.R,
# run_diagnostics_only.R, run_feasibility_only.R) source it automatically
# when present.
#
# BigQuery via JDBC + Application Default Credentials (OAuthType=3).
# Prerequisites:
#   1. gcloud auth application-default login   (run once in terminal)
#   2. BQ_DRIVER_PATH env var in ~/.Renviron pointing to Simba JDBC driver dir
#      e.g.  BQ_DRIVER_PATH="/path/to/jdbc/bigquery-driver"

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "bigquery",
  connectionString = paste0(
    "jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;",
    "ProjectId=YOUR_GCP_PROJECT;",
    "OAuthType=3;",
    "EnableSession=1"
  ),
  pathToDriver = Sys.getenv("BQ_DRIVER_PATH"),
  user = "",
  password = ""
)

# --- Settings -----------------------------------------------------------------
# run_diagnostics_only.R only needs cdmDatabaseSchema, minCellCount, outputFolder.
# run_feasibility_only.R needs the full list below (study-specific defaults are
# defined in the script; values here override them).
settings <- list(
  databaseId          = "YOUR_SITE_ID",
  cdmDatabaseSchema   = "YOUR_GCP_PROJECT.YOUR_CDM_DATASET",
  vocabDatabaseSchema = "YOUR_GCP_PROJECT.YOUR_CDM_DATASET",
  workDatabaseSchema  = "YOUR_GCP_PROJECT.YOUR_WRITE_DATASET",

  # Work tables (defaults from run_feasibility_only.R; override here if needed)
  cohortTable          = "bc_cohort",
  labCohortTable       = "bc_lab_cohort",
  rawLabResultsTable   = "bc_raw_lab_results",
  covariateCohortTable = "bc_covariate_cohort",
  artemisCohortName    = "ARTEMIS bladder cohort",
  episodeTable         = "bc_artemis_episodes",
  regimenClassTable    = "bc_regimen_classifications",

  # Run settings
  minCellCount        = 5L,
  labWindowBeforeDays = 14L,
  labWindowAfterDays  = 7L,
  stripEndocrineTherapy = TRUE,
  validDrugsRegimenComponents = TRUE,
  validDrugsAtcClasses = c("L01", "L02", "L03", "L04"),
  assessmentAtcClasses = NULL,
  outputFolder        = file.path("results")
)

# BigQuery has no real temp tables — SqlRender emulates them as permanent
# tables in this dataset. Point to a dataset you have write access to.
options(sqlRenderTempEmulationSchema = "YOUR_GCP_PROJECT.YOUR_WRITE_DATASET")
