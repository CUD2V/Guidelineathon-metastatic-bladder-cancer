# ===========================================================================
# helpers.R  —  self-contained cohort-generation + SQL utilities
# ===========================================================================
# Thin reimplementations of the OncoStudyModules orchestration using the OHDSI
# packages directly (CirceR, CohortGenerator, SqlRender, DatabaseConnector), so
# this project has no dependency on OncoStudyModules.
# ===========================================================================

# --- read JSON cohort definitions from a directory tree --------------------
# Manifest name = filename with "_" -> " " (matches the study convention).
readJsonCohorts <- function(dir) {
  files <- list.files(dir, pattern = "[.]json$", recursive = TRUE, full.names = TRUE)
  tibble::tibble(
    cohortName = gsub("_", " ", tools::file_path_sans_ext(basename(files))),
    json       = vapply(files, function(f) readr::read_file(f), character(1)),
    file       = files
  )
}

# --- CirceR: cohort-expression JSON -> OHDSI cohort SQL --------------------
# generateStats = TRUE bakes Circe's inclusion-rule-statistics SQL into the
# query (populates cohort_inclusion / cohort_inclusion_stats / cohort_summary_stats
# on generation) — only worth it for JSON cohorts with named InclusionRules
# whose attrition we actually want (Target 1A).
jsonToCohortSql <- function(json, generateStats = FALSE) {
  expr <- CirceR::cohortExpressionFromJson(json)
  CirceR::buildCohortQuery(expr, CirceR::createGenerateOptions(generateStats = generateStats))
}

# --- assemble a CohortGenerator cohortDefinitionSet ------------------------
# `jsonCohorts`  : tibble(cohortName, json) — SQL built via CirceR.
# `customCohorts`: tibble(cohortName, sql)  — pre-rendered SQL templates
#                  (leave @target_* for CohortGenerator to fill).
# `generateStats`: applies to all `jsonCohorts` rows in this call (see
#                  jsonToCohortSql); custom SQL templates have no Circe
#                  inclusion rules, so it has no effect on them.
buildCohortSet <- function(jsonCohorts = NULL, customCohorts = NULL, startId = 1L,
                           generateStats = FALSE) {
  parts <- list()
  nextId <- as.integer(startId)
  if (!is.null(jsonCohorts) && nrow(jsonCohorts) > 0) {
    j <- jsonCohorts
    j$cohortId <- seq.int(nextId, length.out = nrow(j))
    j$sql <- vapply(j$json, jsonToCohortSql, character(1), generateStats = generateStats)
    nextId <- max(j$cohortId) + 1L
    parts$json <- tibble::tibble(cohortId = j$cohortId, cohortName = j$cohortName,
                                 sql = j$sql, json = j$json)
  }
  if (!is.null(customCohorts) && nrow(customCohorts) > 0) {
    cc <- customCohorts
    cc$cohortId <- seq.int(nextId, length.out = nrow(cc))
    parts$custom <- tibble::tibble(cohortId = cc$cohortId, cohortName = cc$cohortName,
                                   sql = cc$sql, json = NA_character_)
  }
  dplyr::bind_rows(parts)
}

# --- generate a cohortDefinitionSet into the work schema -------------------
generateCohorts <- function(connection, cohortDefinitionSet, dropTables = TRUE,
                            cohortTable = settings$cohortTable) {
  tableNames <- CohortGenerator::getCohortTableNames(cohortTable = cohortTable)
  if (dropTables) {
    CohortGenerator::dropCohortStatsTables(
      connection = connection, cohortDatabaseSchema = settings$workDatabaseSchema,
      cohortTableNames = tableNames, dropCohortTable = TRUE) |> suppressWarnings() |> try(silent = TRUE)
  }
  CohortGenerator::createCohortTables(
    connection = connection, cohortDatabaseSchema = settings$workDatabaseSchema,
    cohortTableNames = tableNames, incremental = FALSE)

  # Fill @vocabulary_database_schema up-front (CirceR SQL references it); the
  # rest (@cdm/@target_*) are filled by generateCohortSet.
  cds <- cohortDefinitionSet
  cds$sql <- vapply(cds$sql, function(s)
    SqlRender::render(s, vocabulary_database_schema = settings$vocabDatabaseSchema,
                      warnOnMissingParameters = FALSE), character(1))

  CohortGenerator::generateCohortSet(
    connection = connection, cdmDatabaseSchema = settings$cdmDatabaseSchema,
    cohortDatabaseSchema = settings$workDatabaseSchema,
    cohortTableNames = tableNames, cohortDefinitionSet = cds, incremental = FALSE)

  counts <- CohortGenerator::getCohortCounts(
    connection = connection, cohortDatabaseSchema = settings$workDatabaseSchema,
    cohortTable = tableNames$cohortTable, cohortDefinitionSet = cds)
  # Select only the count columns: some CohortGenerator versions merge the whole
  # cohortDefinitionSet (cohortName/sql/json) into getCohortCounts()'s result,
  # which would duplicate cohortName (.x/.y) and drag sql/json into the join.
  dplyr::left_join(cds[c("cohortId", "cohortName")],
                   counts[c("cohortId", "cohortEntries", "cohortSubjects")],
                   by = "cohortId")
}

# --- render + translate + execute a .sql file ------------------------------
runSqlFile <- function(connection, file, ...) {
  sql <- paste(readLines(file.path(sqlDir, file), warn = FALSE), collapse = "\n")
  sql <- SqlRender::render(sql, ..., warnOnMissingParameters = FALSE)
  if (.getDbms(connection) == "bigquery") sql <- .splitInsertUnionAll(sql)
  sql <- SqlRender::translate(sql, targetDialect = .getDbms(connection))
  DatabaseConnector::executeSql(connection, sql)
}

# --- render + translate + query a .sql file --------------------------------
querySqlFile <- function(connection, file, ...) {
  sql <- paste(readLines(file.path(sqlDir, file), warn = FALSE), collapse = "\n")
  sql <- SqlRender::render(sql, ..., warnOnMissingParameters = FALSE)
  if (.getDbms(connection) == "bigquery") sql <- .splitInsertUnionAll(sql)
  sql <- SqlRender::translate(sql, targetDialect = .getDbms(connection))
  DatabaseConnector::querySql(connection, sql)
}

# --- BigQuery workaround: split INSERT...UNION ALL into separate INSERTs ---
# SqlRender's BigQuery translator incorrectly replaces column references with
# ordinal integers in 2nd+ branches of a UNION ALL (OHDSI/SqlRender#249).
# Workaround: find each INSERT INTO ... (...) SELECT ... UNION ALL SELECT ...
# in the raw SQL and replace with separate INSERT statements. This operates
# directly on the SQL string — no split/reassemble — so all original
# semicolons, comments, and formatting are preserved.
# Only activated when targetDialect is "bigquery"; other dialects skip this.
.splitInsertUnionAll <- function(sql) {
  insert_re <- "INSERT\\s+INTO\\s+\\S+\\s*\\([^)]+\\)"
  m <- gregexpr(insert_re, sql, ignore.case = TRUE, perl = TRUE)[[1]]
  if (m[1] == -1L) return(sql)

  starts <- as.integer(m)
  lengths <- attr(m, "match.length")

  # Process in reverse order to preserve character positions
  for (k in rev(seq_along(starts))) {
    prefix <- substr(sql, starts[k], starts[k] + lengths[k] - 1L)
    body_start <- starts[k] + lengths[k]

    # Find the statement-ending ; at depth 0 (skipping comments/strings)
    stmt_end <- .findStmtEnd(sql, body_start)
    body <- substr(sql, body_start, stmt_end - 1L)

    if (!grepl("\\bUNION\\s+ALL\\b", body, ignore.case = TRUE, perl = TRUE)) next

    # Split body on top-level UNION ALL (not inside parentheses)
    branches <- .splitTopLevelUnionAll(body)
    if (length(branches) <= 1L) next

    # Rebuild as separate INSERT statements
    parts <- vapply(branches, function(b) {
      b <- trimws(b)
      if (nzchar(b)) paste0(prefix, "\n", b) else ""
    }, character(1))
    parts <- parts[nzchar(parts)]
    if (length(parts) == 0L) next

    replacement <- paste(parts, collapse = ";\n")

    # Splice into the SQL string (preserves the original ; at stmt_end)
    before <- if (starts[k] > 1L) substr(sql, 1L, starts[k] - 1L) else ""
    after <- substr(sql, stmt_end, nchar(sql))
    sql <- paste0(before, replacement, after)
  }

  sql
}

# Find the position of the statement-ending ; at parenthesis depth 0,
# correctly skipping line comments (--), block comments (/* */), and
# single-quoted strings.
.findStmtEnd <- function(sql, start) {
  chars <- strsplit(sql, "")[[1]]
  n <- length(chars)
  depth <- 0L
  i <- as.integer(start)

  while (i <= n) {
    ch <- chars[i]
    # Line comment: skip to newline
    if (ch == "-" && i < n && chars[i + 1L] == "-") {
      while (i <= n && chars[i] != "\n") i <- i + 1L
      next
    }
    # Block comment: skip to */
    if (ch == "/" && i < n && chars[i + 1L] == "*") {
      i <- i + 2L
      while (i < n && !(chars[i] == "*" && chars[i + 1L] == "/")) i <- i + 1L
      i <- i + 2L
      next
    }
    # Single-quoted string: skip to closing quote
    if (ch == "'") {
      i <- i + 1L
      while (i <= n) {
        if (chars[i] == "'" && i < n && chars[i + 1L] == "'") {
          i <- i + 2L
        } else if (chars[i] == "'") {
          i <- i + 1L
          break
        } else {
          i <- i + 1L
        }
      }
      next
    }
    if (ch == "(") depth <- depth + 1L
    else if (ch == ")") depth <- depth - 1L
    else if (depth == 0L && ch == ";") return(i)
    i <- i + 1L
  }
  n + 1L
}

# Split SQL text on UNION ALL that appears at parenthesis depth 0.
# UNION ALL inside subqueries (depth > 0) is left intact.
.splitTopLevelUnionAll <- function(sql) {
  chars <- strsplit(sql, "")[[1]]
  n <- length(chars)
  upper <- toupper(sql)
  depth <- 0L
  pieces <- list()
  seg_start <- 1L
  i <- 1L

  while (i <= n) {
    ch <- chars[i]
    if (ch == "(") {
      depth <- depth + 1L
    } else if (ch == ")") {
      depth <- depth - 1L
    } else if (depth == 0L && ch %in% c("U", "u") && i + 8L <= n) {
      candidate <- substr(upper, i, i + 8L)
      if (grepl("^UNION\\s+ALL", candidate)) {
        ua <- regexpr("^UNION\\s+ALL", candidate)
        skip <- attr(ua, "match.length")
        pieces <- c(pieces, substr(sql, seg_start, i - 1L))
        i <- i + skip
        seg_start <- i
        next
      }
    }
    i <- i + 1L
  }
  pieces <- c(pieces, substr(sql, seg_start, n))
  as.character(pieces)
}

# --- write a result data frame to results/eligibility ----------------------
writeResultCsv <- function(df, name) {
  d <- file.path(settings$outputFolder, "eligibility")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, file.path(d, paste0(name, ".csv")), na = "")
}

# --- id lookup for a generated cohort by manifest name ---------------------
cohortIdByName <- function(manifest, name) {
  hit <- manifest$cohortId[manifest$cohortName == name]
  if (length(hit) == 0L) NA_integer_ else as.integer(hit[1])
}
