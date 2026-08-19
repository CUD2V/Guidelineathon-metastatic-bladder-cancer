-- 1) Population prevalence
-- BigQuery compat: GROUPING SETS rewritten as UNION ALL of overall + per-year.
WITH base AS (
    SELECT
        'OVERALL' AS prevalence_year,
        COUNT(*) AS n_patients,
        SUM(CASE WHEN first_other_dx_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_other_dx,
        SUM(CASE WHEN first_gen_cancer_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_gen_cancer_dx,
        SUM(CASE WHEN first_met_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_met,
        SUM(CASE WHEN first_l01_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_l01
    FROM #patient_char

    UNION ALL

    SELECT
        CAST(YEAR(index_date) AS VARCHAR(4)) AS prevalence_year,
        COUNT(*) AS n_patients,
        SUM(CASE WHEN first_other_dx_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_other_dx,
        SUM(CASE WHEN first_gen_cancer_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_gen_cancer_dx,
        SUM(CASE WHEN first_met_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_met,
        SUM(CASE WHEN first_l01_date IS NOT NULL THEN 1 ELSE 0 END) AS n_with_l01
    FROM #patient_char
    GROUP BY YEAR(index_date)
)
SELECT
    prevalence_year,
    CASE WHEN n_patients <= @min_cell_count THEN -@min_cell_count ELSE n_patients END AS n_dx,
    CASE
        WHEN n_patients <= @min_cell_count THEN -@min_cell_count
        WHEN n_with_other_dx BETWEEN 1 AND @min_cell_count THEN -@min_cell_count
        ELSE n_with_other_dx
    END AS n_odx,
    CASE
        WHEN n_patients <= @min_cell_count THEN -@min_cell_count
        WHEN n_with_gen_cancer_dx BETWEEN 1 AND @min_cell_count THEN -@min_cell_count
        ELSE n_with_gen_cancer_dx
    END AS n_gdx,
    CASE
        WHEN n_patients <= @min_cell_count THEN -@min_cell_count
        WHEN n_with_met BETWEEN 1 AND @min_cell_count THEN -@min_cell_count
        ELSE n_with_met
    END AS n_met,
    CASE
        WHEN n_patients <= @min_cell_count THEN -@min_cell_count
        WHEN n_with_l01 BETWEEN 1 AND @min_cell_count THEN -@min_cell_count
        ELSE n_with_l01
    END AS n_l01
FROM base
ORDER BY
    CASE WHEN prevalence_year = 'OVERALL' THEN 0 ELSE 1 END,
    CASE WHEN prevalence_year = 'OVERALL' THEN NULL ELSE CAST(prevalence_year AS INT) END
;

