USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE TABLE RAW.PROFILE_REPORT AS
SELECT 'gold' AS dataset, COUNT(*) AS total_rows,
       COUNT(DISTINCT trade_date) AS distinct_dates,
       COUNT(*)-COUNT(close_price) AS missing_close,
       MIN(COALESCE(TRY_TO_DATE(trade_date,'YYYY-MM-DD'),TRY_TO_DATE(trade_date,'DD/MM/YYYY'),TRY_TO_DATE(trade_date,'MM/DD/YYYY'))) AS earliest_date,
       MAX(COALESCE(TRY_TO_DATE(trade_date,'YYYY-MM-DD'),TRY_TO_DATE(trade_date,'DD/MM/YYYY'),TRY_TO_DATE(trade_date,'MM/DD/YYYY'))) AS latest_date,
       SUM(IFF(TRY_TO_NUMBER(REPLACE(close_price,',','')) IS NULL AND close_price IS NOT NULL,1,0)) AS unparseable_prices
FROM RAW.GOLD_PRICES_RAW
UNION ALL
SELECT 'oil', COUNT(*), COUNT(DISTINCT trade_date), COUNT(*)-COUNT(close_price),
       MIN(COALESCE(TRY_TO_DATE(trade_date,'YYYY-MM-DD'),TRY_TO_DATE(trade_date,'DD/MM/YYYY'),TRY_TO_DATE(trade_date,'MM/DD/YYYY'))),
       MAX(COALESCE(TRY_TO_DATE(trade_date,'YYYY-MM-DD'),TRY_TO_DATE(trade_date,'DD/MM/YYYY'),TRY_TO_DATE(trade_date,'MM/DD/YYYY'))),
       SUM(IFF(TRY_TO_NUMBER(REPLACE(close_price,',','')) IS NULL AND close_price IS NOT NULL,1,0))
FROM RAW.OIL_PRICES_RAW;

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 3, 'RAW', 'profile', 'RAW.PROFILE_REPORT',
       NULL, COUNT(*), NULL, 'OK', 'profile snapshot stored'
FROM RAW.PROFILE_REPORT;
