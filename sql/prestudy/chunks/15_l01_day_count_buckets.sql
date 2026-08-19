-- 15) Distribution of distinct L01 event days per patient
--     Shows how many patients have 1, 2-6, 7-11, or 12+ distinct L01 days.
--     Patients with exactly 1 day cannot contribute to gap analyses (chunks 11-12).
--     Source: #l01_event_days (built in 00_setup.sql section L).
--
--     Two subgroups:
--       ALL_L01 : all DX cohort patients with any L01 record
--       MET_L01 : patients who also have a first_met_date
--     Small-cell suppression: n_patients <= @min_cell_count suppressed to -@min_cell_count.

-- BigQuery compat: all GROUP BY clauses are inside CTEs (not the outer SELECT)
-- to avoid SqlRender ordinal replacement bug (OHDSI/SqlRender#249). The UNION ALL
-- CTE has no GROUP BY in either branch.
WITH l01_raw AS (
    SELECT e.person_id, 'ALL_L01' AS subgroup
    FROM #l01_event_days e
    UNION ALL
    SELECT e.person_id, 'MET_L01' AS subgroup
    FROM #l01_event_days e
    JOIN #met_summary ms ON e.person_id = ms.person_id AND ms.first_met_date IS NOT NULL
),
patient_day_counts AS (
    SELECT person_id, subgroup, COUNT(*) AS n_days
    FROM l01_raw
    GROUP BY person_id, subgroup
),
bucketed AS (
    SELECT
        subgroup,
        CASE
            WHEN n_days =  1 THEN '1'
            WHEN n_days <= 6 THEN '2_6'
            WHEN n_days <= 11 THEN '7_11'
            ELSE '12plus'
        END AS days_bucket,
        CASE WHEN COUNT(*) > 0 AND COUNT(*) <= @min_cell_count THEN -@min_cell_count ELSE COUNT(*) END AS n_patients,
        MIN(n_days) AS sort_key
    FROM patient_day_counts
    GROUP BY
        subgroup,
        CASE
            WHEN n_days =  1 THEN '1'
            WHEN n_days <= 6 THEN '2_6'
            WHEN n_days <= 11 THEN '7_11'
            ELSE '12plus'
        END
)
SELECT
    subgroup,
    days_bucket,
    n_patients
FROM bucketed
ORDER BY subgroup, sort_key
;
