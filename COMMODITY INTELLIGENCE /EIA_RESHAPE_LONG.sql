USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE TABLE CLEAN.EIA_OIL_ANNUAL AS
WITH raw_lines AS (
  SELECT LN, LINE
  FROM RAW.EIA_RAWLINES
  WHERE LN >= 6
),
parsed AS (
  SELECT
    LN,
    f.index AS pos,
    f.value::STRING AS token
  FROM raw_lines,
       LATERAL FLATTEN(input => SPLIT(LINE, ',')) f
),
year_val_pairs AS (
  SELECT
    LN,
    FLOOR(pos / 2) AS pair_idx,
    MAX(CASE WHEN pos % 2 = 0 THEN token END) AS yr_str,
    MAX(CASE WHEN pos % 2 = 1 THEN token END) AS val_str
  FROM parsed
  GROUP BY LN, pair_idx
)
SELECT
  TRY_TO_NUMBER(yr_str) AS obs_year,
  TRY_TO_DOUBLE(REPLACE(val_str, ',', '')) AS world_production_mbd
FROM year_val_pairs
WHERE TRY_TO_NUMBER(yr_str) IS NOT NULL
  AND TRY_TO_DOUBLE(REPLACE(val_str, ',', '')) IS NOT NULL
  AND LN = (
    SELECT MAX(LN) FROM RAW.EIA_RAWLINES
    WHERE LINE ILIKE '%World%'
  )
QUALIFY ROW_NUMBER() OVER (PARTITION BY obs_year ORDER BY world_production_mbd DESC) = 1
ORDER BY obs_year;

-- annual expansion

CREATE OR REPLACE TABLE CLEAN.OPEC_PRODUCTION AS
SELECT
  DATEADD(MONTH, m.mo, DATE_FROM_PARTS(a.obs_year, 1, 1)) AS month_start,
  a.world_production_mbd AS opec_production_mbd,
  'ANNUAL_FFILL' AS granularity
FROM CLEAN.EIA_OIL_ANNUAL a,
     LATERAL (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4())-1 AS mo
              FROM TABLE(GENERATOR(ROWCOUNT => 12))) m
QUALIFY ROW_NUMBER() OVER (PARTITION BY month_start ORDER BY a.obs_year DESC) = 1;

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 2, 'CLEAN', 'eia reshape', 'CLEAN.OPEC_PRODUCTION',
       (SELECT COUNT(*) FROM CLEAN.EIA_OIL_ANNUAL), COUNT(*), NULL,
       IFF(COUNT(*)>0,'OK','WARN'),
       'annual World series expanded to monthly (forward-filled); change-points are annual only'
FROM CLEAN.OPEC_PRODUCTION;


