USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE TABLE ANALYTICS.RECOMMENDATIONS AS
WITH h AS (SELECT * FROM ANALYTICS.V_HYPOTHESIS_SCORED)
SELECT
  ROW_NUMBER() OVER (ORDER BY hypothesis_id) AS rec_id,
  hypothesis_id AS evidence,
  CASE hypothesis_id
    WHEN 'H1' THEN 'Dollar / safe-haven'
    WHEN 'H2' THEN 'Inflation hedge'
    WHEN 'H3' THEN 'Oil supply (World output)'
    WHEN 'H4' THEN 'Volatility regime'
    WHEN 'H5' THEN 'Gold vs VIX dynamics'
    WHEN 'H6' THEN 'Gold vs dollar dynamics'
  END AS theme,
  readout AS finding,
  CASE WHEN verdict_95='REJECT H0' AND power_flag='ADEQUATE' THEN 'HIGH'
       WHEN verdict_95='REJECT H0' THEN 'MODERATE (underpowered)'
       ELSE 'LOW (no significant effect)' END AS confidence,
  CASE hypothesis_id
    WHEN 'H1' THEN IFF(verdict_95='REJECT H0',
         'Tilt gold exposure up when the dollar is weakening; use DXY direction as a positioning signal.',
         'Do not rely on dollar direction alone to time gold in this window.')
    WHEN 'H2' THEN IFF(verdict_95='REJECT H0',
         'Treat gold as a partial inflation hedge; lean in during above-trend CPI prints.',
         'Inflation alone is a weak gold timing signal here — combine with rates/dollar.')
    WHEN 'H3' THEN 'Use World-supply changes as a slow, structural oil signal only; refresh with a true monthly crude series before trading on it (current grain is annual).'
    WHEN 'H4' THEN IFF(verdict_95='REJECT H0',
         'Add gold as portfolio insurance ahead of/within high-VIX regimes.',
         'High-VIX months did not reliably lift gold in this sample — size the safe-haven trade modestly.')
    WHEN 'H5' THEN IFF(verdict_95='REJECT H0',
         'Incorporate VIX moves into a gold-return model; monitor as a risk indicator.',
         'VIX changes are not a reliable linear driver of monthly gold returns here.')
    WHEN 'H6' THEN IFF(verdict_95='REJECT H0',
         'Hedge gold positions against dollar strength; the inverse link is measurable.',
         'Dollar/gold inverse link is weak in this window — validate on a longer series.')
  END AS recommended_action,
  power_flag, p_value
FROM h ORDER BY hypothesis_id;

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 8, 'ANALYTICS', 'recommendations', 'ANALYTICS.RECOMMENDATIONS',
       NULL, COUNT(*), NULL, IFF(COUNT(*)>0,'OK','WARN'),
       SUM(IFF(confidence='HIGH',1,0))||' high-confidence actions'
FROM ANALYTICS.RECOMMENDATIONS;

SELECT * FROM ANALYTICS.RECOMMENDATIONS ORDER BY rec_id;
