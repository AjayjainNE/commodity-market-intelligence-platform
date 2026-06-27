USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

-- Volatility regime profiling

CREATE OR REPLACE TABLE ANALYTICS.VOLATILITY_PROFILE AS
WITH signals AS (
  SELECT *,
         CASE
           WHEN vix < 15 THEN 'LOW'
           WHEN vix BETWEEN 15 AND 25 THEN 'MEDIUM'
           WHEN vix > 25 THEN 'HIGH'
         END AS vix_regime,
         100 * (avg_gold - LAG(avg_gold) OVER (ORDER BY month_start))
             / NULLIF(LAG(avg_gold) OVER (ORDER BY month_start), 0) AS gold_return_pct,
         100 * (avg_oil - LAG(avg_oil) OVER (ORDER BY month_start))
             / NULLIF(LAG(avg_oil) OVER (ORDER BY month_start), 0) AS oil_return_pct
  FROM ANALYTICS.V_MARKET_SIGNALS
  WHERE in_overlap_window
)
SELECT vix_regime, COUNT(*) AS months,
  ROUND(AVG(vix),2) AS avg_vix, ROUND(AVG(vix_vol_of_vol),2) AS avg_vol_of_vol,
  ROUND(AVG(gold_return_pct),2) AS avg_gold_return_pct,
  ROUND(AVG(oil_return_pct),2) AS avg_oil_return_pct
FROM signals
WHERE vix_regime IS NOT NULL
GROUP BY vix_regime
ORDER BY avg_vix;

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 6, 'ANALYTICS', 'volatility profile',
       'ANALYTICS.VOLATILITY_PROFILE', NULL, COUNT(*), NULL,
       IFF(COUNT(*)>0,'OK','WARN'), 'regimes profiled'
FROM ANALYTICS.VOLATILITY_PROFILE;

SELECT * FROM ANALYTICS.VOLATILITY_PROFILE;