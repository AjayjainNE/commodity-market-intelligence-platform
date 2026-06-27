USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE VIEW ANALYTICS.V_EXECUTIVE_BRIEF AS
WITH latest AS (
  SELECT * FROM ANALYTICS.V_MARKET_SIGNALS QUALIFY ROW_NUMBER() OVER (ORDER BY month_start DESC)=1
),
span AS (
  SELECT MIN(month_start) lo, MAX(month_start) hi, COUNT(*) n FROM ANALYTICS.V_MARKET_SIGNALS
)
SELECT 1 AS ord, 'CONTEXT' AS section, 'Analysis window (cross-asset overlap)' AS headline,
       'Gold, oil, dollar, inflation and VIX analysed monthly from '||(SELECT lo FROM span)||
       ' to '||(SELECT hi FROM span)||' ('||(SELECT n FROM span)||' months).' AS detail
UNION ALL
SELECT 2,'KPI','Latest market snapshot',
       'Gold ~'||ROUND((SELECT avg_gold FROM latest),0)||', Oil ~'||ROUND((SELECT avg_oil FROM latest),0)||
       ', VIX regime: '||(SELECT vix_regime FROM latest)||', YoY inflation: '||
       ROUND((SELECT inflation_yoy_pct FROM latest),1)||'%.'
UNION ALL
SELECT 3, 'FINDING', theme, finding FROM ANALYTICS.RECOMMENDATIONS
UNION ALL
SELECT 4, 'RECOMMENDATION', theme||' ('||confidence||')', recommended_action FROM ANALYTICS.RECOMMENDATIONS
ORDER BY ord, headline;

SELECT * FROM ANALYTICS.V_EXECUTIVE_BRIEF;
