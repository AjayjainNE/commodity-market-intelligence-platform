USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;


CREATE OR REPLACE TABLE ANALYTICS.HYPOTHESIS_RESULTS (
  hypothesis_id STRING, hypothesis STRING, test STRING,
  group_a STRING, group_b STRING, n_a NUMBER, n_b NUMBER,
  effect FLOAT, test_statistic FLOAT, p_value FLOAT,
  verdict_95 STRING, grain STRING
);

-- H1 dollar-direction split
INSERT INTO ANALYTICS.HYPOTHESIS_RESULTS
WITH base AS (
  SELECT IFF(dxy_change_pct<0,'dollar_weakened','dollar_strengthened') grp, gold_return_pct y
  FROM ANALYTICS.V_MARKET_SIGNALS WHERE dxy_change_pct IS NOT NULL AND gold_return_pct IS NOT NULL),
s AS (SELECT grp,COUNT(*) n,AVG(y) m,VAR_SAMP(y) v FROM base GROUP BY grp),
ab AS (SELECT MAX(IFF(grp='dollar_weakened',n,NULL)) na,MAX(IFF(grp='dollar_weakened',m,NULL)) ma,MAX(IFF(grp='dollar_weakened',v,NULL)) va,
              MAX(IFF(grp='dollar_strengthened',n,NULL)) nb,MAX(IFF(grp='dollar_strengthened',m,NULL)) mb,MAX(IFF(grp='dollar_strengthened',v,NULL)) vb FROM s)
SELECT 'H1','Gold returns are higher in months when the US dollar weakens','Welch two-sample t-test',
       'dollar_weakened','dollar_strengthened',na,nb,ROUND(ma-mb,4),
       ROUND((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0),4),
       ROUND(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0)),4),
       IFF(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0))<0.05,'REJECT H0','fail to reject H0'),'monthly'
FROM ab;

-- H2 inflation split
INSERT INTO ANALYTICS.HYPOTHESIS_RESULTS
WITH base AS (
  SELECT IFF(inflation_yoy_pct>=AVG(inflation_yoy_pct) OVER (),'high_inflation','low_inflation') grp, gold_return_pct y
  FROM ANALYTICS.V_MARKET_SIGNALS WHERE inflation_yoy_pct IS NOT NULL AND gold_return_pct IS NOT NULL),
s AS (SELECT grp,COUNT(*) n,AVG(y) m,VAR_SAMP(y) v FROM base GROUP BY grp),
ab AS (SELECT MAX(IFF(grp='high_inflation',n,NULL)) na,MAX(IFF(grp='high_inflation',m,NULL)) ma,MAX(IFF(grp='high_inflation',v,NULL)) va,
              MAX(IFF(grp='low_inflation',n,NULL)) nb,MAX(IFF(grp='low_inflation',m,NULL)) mb,MAX(IFF(grp='low_inflation',v,NULL)) vb FROM s)
SELECT 'H2','Gold returns are higher in above-average inflation months','Welch two-sample t-test',
       'high_inflation','low_inflation',na,nb,ROUND(ma-mb,4),
       ROUND((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0),4),
       ROUND(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0)),4),
       IFF(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0))<0.05,'REJECT H0','fail to reject H0'),'monthly'
FROM ab;

-- H3 OPEC supply — ANNUAL grain (honest: EIA data is annual; ~5 change-points).
INSERT INTO ANALYTICS.HYPOTHESIS_RESULTS
WITH base AS (
  SELECT IFF(prod_change_mbd<0,'prod_cut','prod_increase') grp, oil_return_yoy_pct y
  FROM ANALYTICS.V_OIL_ANNUAL WHERE prod_change_mbd IS NOT NULL AND prod_change_mbd<>0 AND oil_return_yoy_pct IS NOT NULL),
s AS (SELECT grp,COUNT(*) n,AVG(y) m,VAR_SAMP(y) v FROM base GROUP BY grp),
ab AS (SELECT MAX(IFF(grp='prod_cut',n,NULL)) na,MAX(IFF(grp='prod_cut',m,NULL)) ma,MAX(IFF(grp='prod_cut',v,NULL)) va,
              MAX(IFF(grp='prod_increase',n,NULL)) nb,MAX(IFF(grp='prod_increase',m,NULL)) mb,MAX(IFF(grp='prod_increase',v,NULL)) vb FROM s)
SELECT 'H3','Annual oil returns are higher in years World oil output falls','Welch two-sample t-test (ANNUAL)',
       'prod_cut','prod_increase',na,nb,ROUND(ma-mb,4),
       ROUND((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0),4),
       ROUND(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0)),4),
       IFF(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0))<0.05,'REJECT H0','fail to reject H0'),'annual'
FROM ab;

-- H4 VIX regime split
INSERT INTO ANALYTICS.HYPOTHESIS_RESULTS
WITH base AS (
  SELECT vix_regime grp, gold_return_pct y FROM ANALYTICS.V_MARKET_SIGNALS
  WHERE vix_regime IN ('stressed','calm') AND gold_return_pct IS NOT NULL),
s AS (SELECT grp,COUNT(*) n,AVG(y) m,VAR_SAMP(y) v FROM base GROUP BY grp),
ab AS (SELECT MAX(IFF(grp='stressed',n,NULL)) na,MAX(IFF(grp='stressed',m,NULL)) ma,MAX(IFF(grp='stressed',v,NULL)) va,
              MAX(IFF(grp='calm',n,NULL)) nb,MAX(IFF(grp='calm',m,NULL)) mb,MAX(IFF(grp='calm',v,NULL)) vb FROM s)
SELECT 'H4','Gold returns are higher in high-VIX (stressed) vs calm months','Welch two-sample t-test',
       'vix_stressed','vix_calm',na,nb,ROUND(ma-mb,4),
       ROUND((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0),4),
       ROUND(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0)),4),
       IFF(AUDIT.TWO_SIDED_P((ma-mb)/NULLIF(SQRT(va/na+vb/nb),0))<0.05,'REJECT H0','fail to reject H0'),'monthly'
FROM ab;

-- H5 OLS gold_return ~ vix_change
INSERT INTO ANALYTICS.HYPOTHESIS_RESULTS
WITH d AS (SELECT gold_return_pct y,vix_change x FROM ANALYTICS.V_MARKET_SIGNALS WHERE gold_return_pct IS NOT NULL AND vix_change IS NOT NULL),
m AS (SELECT COUNT(*) n,REGR_SLOPE(y,x) slope,CORR(y,x) r FROM d)
SELECT 'H5','Monthly gold returns are linearly related to changes in VIX','OLS slope (corr significance)',
       'gold_return ~ vix_change',NULL,n,NULL,ROUND(slope,4),
       ROUND(r*SQRT((n-2)/NULLIF(1-r*r,0)),4),
       ROUND(AUDIT.TWO_SIDED_P(r*SQRT((n-2)/NULLIF(1-r*r,0))),4),
       IFF(AUDIT.TWO_SIDED_P(r*SQRT((n-2)/NULLIF(1-r*r,0)))<0.05,'REJECT H0','fail to reject H0'),'monthly'
FROM m;

-- H6 OLS gold_return ~ dxy_change
INSERT INTO ANALYTICS.HYPOTHESIS_RESULTS
WITH d AS (SELECT gold_return_pct y,dxy_change_pct x FROM ANALYTICS.V_MARKET_SIGNALS WHERE gold_return_pct IS NOT NULL AND dxy_change_pct IS NOT NULL),
m AS (SELECT COUNT(*) n,REGR_SLOPE(y,x) slope,CORR(y,x) r FROM d)
SELECT 'H6','Monthly gold returns move inversely with the dollar','OLS slope (corr significance)',
       'gold_return ~ dxy_change',NULL,n,NULL,ROUND(slope,4),
       ROUND(r*SQRT((n-2)/NULLIF(1-r*r,0)),4),
       ROUND(AUDIT.TWO_SIDED_P(r*SQRT((n-2)/NULLIF(1-r*r,0))),4),
       IFF(AUDIT.TWO_SIDED_P(r*SQRT((n-2)/NULLIF(1-r*r,0)))<0.05,'REJECT H0','fail to reject H0'),'monthly'
FROM m;

-- Scored view: attach min_n, power flag, and a plain-English readout to each test.
CREATE OR REPLACE VIEW ANALYTICS.V_HYPOTHESIS_SCORED AS
SELECT *,
  COALESCE(LEAST(NVL(n_a,n_b), NVL(n_b,n_a)), n_a, n_b) AS min_n,
  CASE
    WHEN COALESCE(LEAST(NVL(n_a,n_b),NVL(n_b,n_a)),n_a,n_b) >= 30 THEN 'ADEQUATE'
    WHEN COALESCE(LEAST(NVL(n_a,n_b),NVL(n_b,n_a)),n_a,n_b) >= 15 THEN 'LOW POWER'
    ELSE 'VERY LOW POWER'
  END AS power_flag,
  CASE WHEN verdict_95='REJECT H0'
       THEN 'Significant at 95% (normal approx). '
       ELSE 'Not significant at 95%. ' END ||
  'n='||COALESCE(LEAST(NVL(n_a,n_b),NVL(n_b,n_a)),n_a,n_b)||
  IFF(grain='annual',' [ANNUAL grain — interpret with caution]','') AS readout
FROM ANALYTICS.HYPOTHESIS_RESULTS;

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT $run_id, $run_started, 7, 'TEST', 'hypothesis tests', 'ANALYTICS.HYPOTHESIS_RESULTS',
       NULL, COUNT(*), NULL, IFF(COUNT(*)=6,'OK','WARN'),
       SUM(IFF(verdict_95='REJECT H0',1,0))||' of '||COUNT(*)||' rejected H0; '||
       SUM(IFF(power_flag<>'ADEQUATE',1,0))||' underpowered'
FROM ANALYTICS.V_HYPOTHESIS_SCORED;

SELECT hypothesis_id, hypothesis, test, n_a, n_b, effect, test_statistic,
       p_value, verdict_95, power_flag, readout
FROM ANALYTICS.V_HYPOTHESIS_SCORED ORDER BY hypothesis_id;





