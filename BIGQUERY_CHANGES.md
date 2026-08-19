# BigQuery Compatibility Changes

SQL modifications required to run the FALCON pre-study diagnostics against a
Google BigQuery OMOP CDM via the Simba JDBC driver. All changes are
**syntax-only** — no query semantics were altered. Each change works around a
known limitation in either BigQuery's SQL dialect or in SqlRender's BigQuery
translator.

## Root causes

### 1. SqlRender bug #249 — UNION ALL ordinal replacement

SqlRender's BigQuery translator replaces column references with positional
ordinals in GROUP BY / SELECT of UNION ALL queries. When the ordinals are
computed incorrectly the translated SQL references the wrong columns (e.g.
pointing GROUP BY at an aggregate function). The bug triggers whenever *any*
CTE or subquery in the statement contains a UNION ALL with GROUP BY inside its
branches; it then mangles GROUP BY clauses throughout the entire statement —
including the outer SELECT.

**Workaround pattern (used in chunks 05, 15, 17):** Separate the UNION ALL
from the GROUP BY into different CTEs. The CTE containing the UNION ALL must
have *no* GROUP BY in any branch. Aggregation is performed in a downstream
CTE that references the UNION ALL CTE by name.

**Workaround pattern (used in chunks 03, 14):** For simpler cases where the
GROUP BY is not in the UNION ALL branches, wrapping bare column references in
`CAST(col AS VARCHAR(n))` in the SELECT list prevents SqlRender from replacing
them with ordinals.

### 2. GROUPING SETS not supported

BigQuery does not support `GROUP BY GROUPING SETS`. These are rewritten as
the equivalent UNION ALL of an overall aggregate (no GROUP BY) and a per-year
aggregate (GROUP BY YEAR(...)).

### 3. IN subquery not allowed inside JOIN predicates

BigQuery does not allow `column IN (SELECT ...)` inside a JOIN's ON clause.
The subquery filter is moved to a pre-filtering CTE using INNER JOIN instead.

### 4. CTE scope lost when INSERT...UNION ALL is split

The `R/helpers.R` UNION ALL splitter (`.splitInsertUnionAll()`) splits
`INSERT INTO ... SELECT ... UNION ALL SELECT ...` into separate INSERT
statements for BigQuery compatibility. When the original statement uses a
WITH clause, the CTEs are not propagated to the second INSERT. The fix
duplicates the CTE definitions into each INSERT statement.

## Changed files

### `sql/prestudy/chunks/00_setup.sql`

| Section | Change | Cause |
|---------|--------|-------|
| `#death_stratum_counts` INSERT (INDEX anchor) | `GROUPING SETS` rewritten as two separate INSERTs: one OVERALL (no GROUP BY), one per-year (GROUP BY YEAR) | #2 |
| `#death_stratum_counts` INSERT (FIRST_MET anchor) | Same GROUPING SETS rewrite | #2 |
| `#l01_consecutive_gaps` INSERT | Single CTE+INSERT...UNION ALL split into two CTE+INSERT statements, each carrying its own copy of the `ranked`/`gaps` CTEs | #4 |

### `sql/prestudy/chunks/01_population_prevalence.sql`

`GROUP BY GROUPING SETS ((), (YEAR(index_date)))` rewritten as UNION ALL of an
overall aggregate and a per-year aggregate. (Cause #2)

### `sql/prestudy/chunks/03_directionality_buckets.sql`

Bare `direction` column references in all 6 UNION ALL branches wrapped in
`CAST(direction AS VARCHAR(20))`. (Cause #1)

### `sql/prestudy/chunks/05_timing_by_year.sql`

Restructured from an inline FROM subquery (two UNION ALL branches, each with
GROUP BY and window functions) into three CTEs:
- `pairs_raw` — UNION ALL of raw rows from both timing types (no GROUP BY)
- `pairs_ranked` — window functions partitioned by `timing_type` to keep
  rankings independent per timing type
- `agg` — GROUP BY aggregation (no UNION ALL)

The outer SELECT is a pass-through with small-cell suppression. (Cause #1)

### `sql/prestudy/chunks/14_death_gap_buckets.sql`

Bare `gap_bucket` column references in both UNION ALL branches wrapped in
`CAST(gap_bucket AS VARCHAR(20))`. (Cause #1)

### `sql/prestudy/chunks/15_l01_day_count_buckets.sql`

Restructured from an inline FROM subquery (two UNION ALL branches, each with
GROUP BY) plus outer GROUP BY, into three CTEs:
- `l01_raw` — UNION ALL of raw rows (no GROUP BY in either branch)
- `patient_day_counts` — per-patient aggregation (GROUP BY person_id, subgroup)
- `bucketed` — bucket aggregation with small-cell suppression

The outer SELECT is a pass-through. (Cause #1)

### `sql/prestudy/chunks/17_e_obs_period_integrity.sql`

Three UNION ALL branches in the `metrics` CTE that contained GROUP BY were
extracted into separate pre-computation CTEs:
- `metric_multi_period` (PATIENTS_WITH_MULTIPLE_OBS_PERIODS)
- `metric_period_after_death` (DECEDENTS_PERIOD_ENDS_AFTER_DEATH)
- `metric_median_past_death` (MEDIAN_DAYS_PERIOD_ENDS_PAST_DEATH)

The `metrics` CTE now references these via `SELECT ... FROM cte_name` — no
branch contains GROUP BY. (Cause #1)

### `sql/prestudy/chunks/40_d_treatment_availability_met_subset.sql`

`IN (SELECT concept_id FROM #dtp_concepts)` inside a LEFT JOIN ON clause moved
to a `dtp_procedures` CTE that pre-filters `procedure_occurrence` via INNER
JOIN to `#dtp_concepts`. The `dtp_flags` CTE then LEFT JOINs to
`dtp_procedures` instead. (Cause #3)
