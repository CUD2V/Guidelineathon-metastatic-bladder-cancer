# site_config.R — site-specific connection details (gitignored)
#
# BigQuery via JDBC + Application Default Credentials (OAuthType=3).
# Requires: gcloud auth application-default login  (run once in terminal)
#           BQ_DRIVER_PATH env var pointing to Simba JDBC driver directory

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "bigquery",
  connectionString = paste0(
    "jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;",
    "ProjectId=hdcdmohdsi;",
    "OAuthType=3;",
    "EnableSession=1"
  ),
  pathToDriver = Sys.getenv("BQ_DRIVER_PATH"),
  user = "",
  password = ""
)

# --- Settings -----------------------------------------------------------------
# run_diagnostics_only.R only needs cdmDatabaseSchema, minCellCount, outputFolder.
# run_study_only.R needs the full list below (study-specific defaults are
# defined in the script; values here override them).
settings <- list(
  databaseId          = "cuanschutz",
  cdmDatabaseSchema   = "hdcdmohdsi.study_falcon_data",
  vocabDatabaseSchema = "hdcdmohdsi.study_falcon_data",
  workDatabaseSchema  = "hdcdmohdsi.study_falcon_results",

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
  labWindowBeforeDays = 30L,   # near-index eligibility inputs (labs, ECOG/PS): days before index
  labWindowAfterDays  = 30L,   # same, days after index
  conditionFlagWindowBeforeDays = 365L,   # pre-existing condition flags: days before index
  conditionFlagWindowAfterDays  = 30L,    # same, days after index
  bodyMeasurementsWindowDays = 90L,   # baseline weight/height/BMI: days before/after index
  stripEndocrineTherapy = TRUE,
  validDrugsRegimenComponents = TRUE,
  validDrugsAtcClasses = c("L01", "L02", "L03", "L04"),
  assessmentAtcClasses = NULL,
  strataColumns = c("age_group", "sex", "age_sex"),   # age/sex breakdowns reported on stratified outputs
  outputFolder        = file.path("results")
)

# BigQuery has no real temp tables — SqlRender emulates them as permanent
# tables in this dataset. Use the write/results dataset.
options(sqlRenderTempEmulationSchema = "hdcdmohdsi.study_falcon_results")
