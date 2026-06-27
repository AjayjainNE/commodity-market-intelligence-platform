USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

SET overlap_floor = (
  SELECT GREATEST(
    (SELECT MIN(DATE_TRUNC('MONTH',trade_date)) FROM CLEAN.GOLD_PRICES),
    (SELECT MIN(DATE_TRUNC('MONTH',trade_date)) FROM CLEAN.OIL_PRICES),
    (SELECT MIN(month_start) FROM CLEAN.DXY),
    (SELECT MIN(month_start) FROM CLEAN.VIX)
  )
);

-- Monthly Facts


CREATE OR REPLACE TABLE ANALYTICS.MONTHLY_MARKET AS
WITH g AS (
  SELECT DATE_TRUNC('MONTH',trade_date) AS month_start,
         AVG(close_price) AS avg_gold,
         STDDEV(close_price)/NULLIF(AVG(close_price),0) AS gold_volatility,
         SUM(volume) AS gold_volume
  FROM CLEAN.GOLD_PRICES GROUP BY 1
),
o AS (
  SELECT DATE_TRUNC('MONTH',trade_date) AS month_start,
         AVG(close_price) AS avg_oil,
         STDDEV(close_price)/NULLIF(AVG(close_price),0) AS oil_volatility,
         SUM(volume) AS oil_volume
  FROM CLEAN.OIL_PRICES GROUP BY 1
)
SELECT g.month_start,
       g.avg_gold, g.gold_volatility, g.gold_volume,
       o.avg_oil,  o.oil_volatility,  o.oil_volume,
       d.dxy_value AS dxy, c.cpi_value AS cpi,
       v.vix_value AS vix, v.vix_vol_of_vol, v.vix_high, v.vix_low,
       p.opec_production_mbd AS opec_production, p.granularity AS opec_granularity,
       IFF(g.month_start >= $overlap_floor AND v.vix_value IS NOT NULL
           AND d.dxy_value IS NOT NULL, TRUE, FALSE) AS in_overlap_window
FROM g
JOIN o USING (month_start)
LEFT JOIN CLEAN.DXY d USING (month_start)
LEFT JOIN CLEAN.CPI c USING (month_start)
LEFT JOIN CLEAN.VIX v USING (month_start)
LEFT JOIN CLEAN.OPEC_PRODUCTION p USING (month_start)
ORDER BY g.month_start;

-- Rolling 12-month correlations (manual formula since CORR doesn't support sliding windows)

CREATE OR REPLACE TABLE ANALYTICS.ROLLING_CORRELATIONS AS
SELECT month_start,
       avg_gold, avg_oil, dxy, vix,
       -- 12-month rolling correlation: gold vs oil
       (AVG(avg_gold * avg_oil) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
        - AVG(avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
          * AVG(avg_oil) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW))
       / NULLIF(SQRT(
           (AVG(avg_gold * avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
            - POWER(AVG(avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2))
           * (AVG(avg_oil * avg_oil) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
            - POWER(AVG(avg_oil) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2))
         ), 0) AS corr_gold_oil_12m,
       -- 12-month rolling correlation: gold vs DXY
       (AVG(avg_gold * dxy) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
        - AVG(avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
          * AVG(dxy) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW))
       / NULLIF(SQRT(
           (AVG(avg_gold * avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
            - POWER(AVG(avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2))
           * (AVG(dxy * dxy) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
            - POWER(AVG(dxy) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2))
         ), 0) AS corr_gold_dxy_12m,
       -- 12-month rolling correlation: gold vs VIX
       (AVG(avg_gold * vix) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
        - AVG(avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
          * AVG(vix) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW))
       / NULLIF(SQRT(
           (AVG(avg_gold * avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
            - POWER(AVG(avg_gold) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2))
           * (AVG(vix * vix) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
            - POWER(AVG(vix) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2))
         ), 0) AS corr_gold_vix_12m
FROM ANALYTICS.MONTHLY_MARKET
WHERE in_overlap_window
ORDER BY month_start;

-- Annual oil/production view for the honest (annual) OPEC test

CREATE OR REPLACE VIEW ANALYTICS.V_OIL_ANNUAL AS
WITH oil_y AS (
  SELECT YEAR(trade_date) AS yr, AVG(close_price) AS avg_oil
  FROM CLEAN.OIL_PRICES GROUP BY 1
)
SELECT y.yr, y.avg_oil, e.world_production_mbd,
       (y.avg_oil/NULLIF(LAG(y.avg_oil) OVER (ORDER BY y.yr),0)-1)*100 AS oil_return_yoy_pct,
       e.world_production_mbd - LAG(e.world_production_mbd) OVER (ORDER BY e.obs_year) AS prod_change_mbd
FROM oil_y y JOIN CLEAN.EIA_OIL_ANNUAL e ON y.yr = e.obs_year;

CREATE OR REPLACE VIEW ANALYTICS.V_EVENT_IMPACT AS
SELECT e.event_date, e.event_type, e.description,
  AVG(IFF(g.trade_date BETWEEN DATEADD(DAY,-30,e.event_date) AND e.event_date, g.close_price, NULL)) AS gold_avg_before,
  AVG(IFF(g.trade_date BETWEEN e.event_date AND DATEADD(DAY,30,e.event_date), g.close_price, NULL)) AS gold_avg_after,
  AVG(IFF(o.trade_date BETWEEN DATEADD(DAY,-30,e.event_date) AND e.event_date, o.close_price, NULL)) AS oil_avg_before,
  AVG(IFF(o.trade_date BETWEEN e.event_date AND DATEADD(DAY,30,e.event_date), o.close_price, NULL)) AS oil_avg_after
FROM CLEAN.MARKET_EVENTS e
LEFT JOIN CLEAN.GOLD_PRICES g ON g.trade_date BETWEEN DATEADD(DAY,-30,e.event_date) AND DATEADD(DAY,30,e.event_date)
LEFT JOIN CLEAN.OIL_PRICES o ON o.trade_date = g.trade_date
GROUP BY 1,2,3;

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 5, 'ANALYTICS', 'monthly fact', 'ANALYTICS.MONTHLY_MARKET',
       NULL, COUNT(*), NULL,
       IFF(SUM(IFF(in_overlap_window,1,0)) >= 24,'OK','WARN'),
       'months_total='||COUNT(*)||', overlap_months='||SUM(IFF(in_overlap_window,1,0))||
       ', overlap_floor='||$overlap_floor
FROM ANALYTICS.MONTHLY_MARKET;


