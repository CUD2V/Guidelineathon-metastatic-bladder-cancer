-- 5) Pairwise timing summary stratified by anchor year
--    Same structure as chunk 04 (final_timing_pairwise.csv) but grouped by year.
--    Year is anchored on the from_event: DX-anchored pairs use YEAR(index_date),
--    MET-anchored pairs use YEAR(first_met_date).
--    Used for year-over-year plots and for the per-year columns in the §06 stability matrix.
--    Small-cell suppression applied.

-- BigQuery compat: GROUP BY lifted out of UNION ALL branches into a separate CTE
-- to avoid SqlRender ordinal replacement bug (OHDSI/SqlRender#249). The UNION ALL
-- in pairs_raw has no GROUP BY, so SqlRender leaves it alone; the GROUP BY in agg
-- has no UNION ALL, so it is also safe.
WITH pairs_raw AS (
    -- first_to_first by anchor year
    SELECT 'first_to_first' AS timing_type,
        p.from_event, p.to_event, p.days_diff,
        CASE WHEN p.from_event = 'MET' THEN YEAR(ms.first_met_date) ELSE YEAR(pc.index_date) END AS index_year_int
    FROM #patient_timing_pairs p
    JOIN #patient_char pc    ON p.person_id = pc.person_id
    LEFT JOIN #met_summary ms ON p.person_id = ms.person_id
    UNION ALL
    -- first_to_closest_after by anchor year (MET-anchored pairs use MET year)
    SELECT 'first_to_closest_after',
        p.from_event, p.to_event, p.days_diff,
        CASE WHEN p.from_event = 'MET' THEN YEAR(ms.first_met_date) ELSE YEAR(pc.index_date) END
    FROM #patient_timing_pairs_first_to_closest_after p
    JOIN #patient_char pc    ON p.person_id = pc.person_id
    LEFT JOIN #met_summary ms ON p.person_id = ms.person_id
),
pairs_ranked AS (
    SELECT
        timing_type, from_event, to_event, days_diff, index_year_int,
        ROW_NUMBER() OVER (PARTITION BY timing_type, index_year_int, from_event, to_event ORDER BY days_diff) AS rn,
        COUNT(*)     OVER (PARTITION BY timing_type, index_year_int, from_event, to_event)                    AS cnt
    FROM pairs_raw
),
agg AS (
    SELECT
        timing_type,
        CAST(index_year_int AS VARCHAR(4)) AS index_year,
        from_event,
        to_event,
        COUNT(*) AS n_patients_with_pair,
        MIN(CASE WHEN 4.0 * rn >= cnt THEN CAST(days_diff AS FLOAT) END) AS p25_days,
        MIN(CASE WHEN 2.0 * rn >= cnt THEN CAST(days_diff AS FLOAT) END) AS p50_days,
        MIN(CASE WHEN 4.0 * rn >= 3 * cnt THEN CAST(days_diff AS FLOAT) END) AS p75_days
    FROM pairs_ranked
    GROUP BY timing_type, CAST(index_year_int AS VARCHAR(4)), from_event, to_event
)
SELECT
    agg.timing_type,
    agg.index_year,
    agg.from_event,
    agg.to_event,
    CASE WHEN agg.n_patients_with_pair <= @min_cell_count THEN -@min_cell_count ELSE agg.n_patients_with_pair END AS n_patients_with_pair,
    CASE WHEN agg.n_patients_with_pair <= @min_cell_count THEN NULL ELSE agg.p25_days  END AS p25_days,
    CASE WHEN agg.n_patients_with_pair <= @min_cell_count THEN NULL ELSE agg.p50_days  END AS p50_days,
    CASE WHEN agg.n_patients_with_pair <= @min_cell_count THEN NULL ELSE agg.p75_days  END AS p75_days
FROM agg
ORDER BY
    agg.timing_type,
    agg.from_event,
    agg.to_event,
    CAST(agg.index_year AS INT)
;
