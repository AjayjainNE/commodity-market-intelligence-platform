USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

CREATE OR REPLACE TABLE CLEAN.GOLD_PRICES AS
WITH parsed AS (
  SELECT
    COALESCE(TRY_TO_DATE(trade_date,'YYYY-MM-DD'),TRY_TO_DATE(trade_date,'DD/MM/YYYY'),TRY_TO_DATE(trade_date,'MM/DD/YYYY')) AS trade_date,
    TRY_TO_NUMBER(REPLACE(close_price,',',''),14,4) AS close_price,
    CASE
      WHEN volume ILIKE '%K' THEN TRY_TO_NUMBER(REPLACE(REPLACE(volume,',',''),'K',''),14,2)*1e3
      WHEN volume ILIKE '%M' THEN TRY_TO_NUMBER(REPLACE(REPLACE(volume,',',''),'M',''),14,2)*1e6
      WHEN volume ILIKE '%B' THEN TRY_TO_NUMBER(REPLACE(REPLACE(volume,',',''),'B',''),14,2)*1e9
      ELSE TRY_TO_NUMBER(REPLACE(volume,',',''),18,0)
    END AS volume, _source_file, _run_id
  FROM RAW.GOLD_PRICES_RAW
)
SELECT trade_date, close_price, volume, _source_file, _run_id, FALSE AS is_outlier
FROM parsed
WHERE trade_date IS NOT NULL AND close_price IS NOT NULL AND close_price > 0
QUALIFY ROW_NUMBER() OVER (PARTITION BY trade_date ORDER BY _source_file DESC) = 1;

UPDATE CLEAN.GOLD_PRICES t SET is_outlier = TRUE
FROM (SELECT trade_date FROM (
        SELECT trade_date,(close_price-AVG(close_price) OVER ())/NULLIF(STDDEV(close_price) OVER (),0) AS z
        FROM CLEAN.GOLD_PRICES) WHERE ABS(z)>3) o
WHERE t.trade_date=o.trade_date;

CREATE OR REPLACE TABLE CLEAN.OIL_PRICES AS
WITH parsed AS (
  SELECT
    COALESCE(TRY_TO_DATE(trade_date,'YYYY-MM-DD'),TRY_TO_DATE(trade_date,'DD/MM/YYYY'),TRY_TO_DATE(trade_date,'MM/DD/YYYY')) AS trade_date,
    TRY_TO_NUMBER(REPLACE(close_price,',',''),14,4) AS close_price,
    CASE
      WHEN volume ILIKE '%K' THEN TRY_TO_NUMBER(REPLACE(REPLACE(volume,',',''),'K',''),14,2)*1e3
      WHEN volume ILIKE '%M' THEN TRY_TO_NUMBER(REPLACE(REPLACE(volume,',',''),'M',''),14,2)*1e6
      WHEN volume ILIKE '%B' THEN TRY_TO_NUMBER(REPLACE(REPLACE(volume,',',''),'B',''),14,2)*1e9
      ELSE TRY_TO_NUMBER(REPLACE(volume,',',''),18,0)
    END AS volume, _source_file, _run_id
  FROM RAW.OIL_PRICES_RAW
)
SELECT trade_date, close_price, volume, _source_file, _run_id, FALSE AS is_outlier
FROM parsed
WHERE trade_date IS NOT NULL AND close_price IS NOT NULL AND close_price > 0
QUALIFY ROW_NUMBER() OVER (PARTITION BY trade_date ORDER BY _source_file DESC) = 1;

UPDATE CLEAN.OIL_PRICES t SET is_outlier = TRUE
FROM (SELECT trade_date FROM (
        SELECT trade_date,(close_price-AVG(close_price) OVER ())/NULLIF(STDDEV(close_price) OVER (),0) AS z
        FROM CLEAN.OIL_PRICES) WHERE ABS(z)>3) o
WHERE t.trade_date=o.trade_date;

CREATE OR REPLACE TABLE CLEAN.DXY AS
SELECT DATE_TRUNC('MONTH',TRY_TO_DATE(obs_date,'YYYY-MM-DD')) AS month_start,
       AVG(TRY_TO_NUMBER(dxy_value,10,4)) AS dxy_value
FROM RAW.DXY_RAW
WHERE TRY_TO_DATE(obs_date,'YYYY-MM-DD') IS NOT NULL AND TRY_TO_NUMBER(dxy_value,10,4) IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE TABLE CLEAN.CPI AS
SELECT DATE_TRUNC('MONTH',TRY_TO_DATE(obs_date,'YYYY-MM-DD')) AS month_start,
       TRY_TO_NUMBER(cpi_value,10,3) AS cpi_value
FROM RAW.CPI_RAW
WHERE TRY_TO_DATE(obs_date,'YYYY-MM-DD') IS NOT NULL AND TRY_TO_NUMBER(cpi_value,10,3) IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY month_start ORDER BY obs_date DESC) = 1;

CREATE OR REPLACE TABLE CLEAN.VIX AS
SELECT DATE_TRUNC('MONTH',TRY_TO_DATE(obs_date,'YYYY-MM-DD')) AS month_start,
       AVG(TRY_TO_NUMBER(vix_value,10,2))    AS vix_value,
       STDDEV(TRY_TO_NUMBER(vix_value,10,2)) AS vix_vol_of_vol,
       MAX(TRY_TO_NUMBER(vix_value,10,2))    AS vix_high,
       MIN(TRY_TO_NUMBER(vix_value,10,2))    AS vix_low,
       COUNT(*)                              AS vix_obs_days
FROM RAW.VIX_RAW
WHERE TRY_TO_DATE(obs_date,'YYYY-MM-DD') IS NOT NULL AND TRY_TO_NUMBER(vix_value,10,2) IS NOT NULL
GROUP BY 1;


CREATE OR REPLACE TABLE CLEAN.QUALITY_REPORT AS
SELECT 'gold' dataset, (SELECT COUNT(*) FROM RAW.GOLD_PRICES_RAW) raw_rows,
       (SELECT COUNT(*) FROM CLEAN.GOLD_PRICES) clean_rows,
       (SELECT COUNT(*) FROM CLEAN.GOLD_PRICES WHERE is_outlier) flagged_outliers
UNION ALL SELECT 'oil',(SELECT COUNT(*) FROM RAW.OIL_PRICES_RAW),(SELECT COUNT(*) FROM CLEAN.OIL_PRICES),(SELECT COUNT(*) FROM CLEAN.OIL_PRICES WHERE is_outlier)
UNION ALL SELECT 'dxy',(SELECT COUNT(*) FROM RAW.DXY_RAW),(SELECT COUNT(*) FROM CLEAN.DXY),0
UNION ALL SELECT 'cpi',(SELECT COUNT(*) FROM RAW.CPI_RAW),(SELECT COUNT(*) FROM CLEAN.CPI),0
UNION ALL SELECT 'vix',(SELECT COUNT(*) FROM RAW.VIX_RAW),(SELECT COUNT(*) FROM CLEAN.VIX),0
UNION ALL SELECT 'opec(eia)',(SELECT COUNT(*) FROM RAW.EIA_WIDE),(SELECT COUNT(*) FROM CLEAN.OPEC_PRODUCTION),0;