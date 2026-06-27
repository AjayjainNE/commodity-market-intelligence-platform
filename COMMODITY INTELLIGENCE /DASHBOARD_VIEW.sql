USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE VIEW ANALYTICS.V_EXECUTIVE_DASHBOARD AS
SELECT s.month_start, s.avg_gold, s.avg_oil,
  s.gold_return_pct, s.oil_return_pct,
  s.gold_volatility*100 AS gold_vol_pct, s.oil_volatility*100 AS oil_vol_pct,
  s.dxy, s.inflation_yoy_pct, s.vix, s.vix_regime, s.vix_change, s.vix_vol_of_vol,
  s.opec_production, s.opec_granularity,
  s.corr_gold_oil_12m, s.corr_gold_dxy_12m, s.corr_gold_vix_12m,
  e.description AS event_in_month
FROM ANALYTICS.V_MARKET_SIGNALS s
LEFT JOIN (
  SELECT DATE_TRUNC('MONTH',event_date) AS month_start, LISTAGG(description,'; ') AS description
  FROM CLEAN.MARKET_EVENTS GROUP BY 1
) e USING (month_start)
ORDER BY s.month_start;

SELECT * FROM ANALYTICS.V_EXECUTIVE_DASHBOARD LIMIT 20;



