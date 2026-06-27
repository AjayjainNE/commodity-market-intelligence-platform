USE WAREHOUSE INTEL_WH;
USE DATABASE  COMMODITY_INTEL;

SET run_id      = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE VIEW ANALYTICS.V_MARKET_SIGNALS AS
WITH derived AS (
  SELECT
    month_start,
    avg_gold,
    avg_oil,
    gold_volatility,
    oil_volatility,
    gold_volume,
    oil_volume,
    dxy,
    cpi,
    vix,
    vix_vol_of_vol,
    vix_high,
    vix_low,
    opec_production,
    opec_granularity,
    in_overlap_window,

    -- month-over-month percentage returns
    100 * (avg_gold - LAG(avg_gold) OVER (ORDER BY month_start))
        / NULLIF(LAG(avg_gold) OVER (ORDER BY month_start), 0) AS gold_return_pct,
    100 * (avg_oil  - LAG(avg_oil)  OVER (ORDER BY month_start))
        / NULLIF(LAG(avg_oil)  OVER (ORDER BY month_start), 0) AS oil_return_pct,

    -- dollar: month-over-month percentage change (consumed by H1, H6)
    100 * (dxy - LAG(dxy) OVER (ORDER BY month_start))
        / NULLIF(LAG(dxy) OVER (ORDER BY month_start), 0) AS dxy_change_pct,

    -- VIX: month-over-month level change in points (consumed by H5; not a %)
    vix - LAG(vix) OVER (ORDER BY month_start) AS vix_change,

    -- inflation: year-over-year % change in CPI (needs 12 prior monthly rows)
    100 * (cpi - LAG(cpi, 12) OVER (ORDER BY month_start))
        / NULLIF(LAG(cpi, 12) OVER (ORDER BY month_start), 0) AS inflation_yoy_pct
  FROM ANALYTICS.MONTHLY_MARKET
)
SELECT
  d.*,
  -- Regime labels consumed by H4 ('stressed' vs 'calm'); 'neutral' is excluded
  -- from that test. Thresholds are tunable: tighten the band (e.g. 20/20 with no
  -- neutral, or a median split) if H4 comes back underpowered.
  CASE
    WHEN d.vix >= 25 THEN 'stressed'
    WHEN d.vix <  17 THEN 'calm'
    ELSE 'neutral'
  END AS vix_regime,
  rc.corr_gold_oil_12m,
  rc.corr_gold_dxy_12m,
  rc.corr_gold_vix_12m
FROM derived d
LEFT JOIN ANALYTICS.ROLLING_CORRELATIONS rc
       ON rc.month_start = d.month_start
ORDER BY d.month_start;

-- Audit log entry 

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 5, 'ANALYTICS', 'market signals view',
       'ANALYTICS.V_MARKET_SIGNALS', NULL, COUNT(*), NULL,
       IFF(COUNT(*) > 0, 'OK', 'WARN'),
       'signal spine built; overlap_months='||SUM(IFF(in_overlap_window, 1, 0))
FROM ANALYTICS.V_MARKET_SIGNALS;

ALTER WAREHOUSE INTEL_WH SUSPEND;
