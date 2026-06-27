USE WAREHOUSE COMMODITY_WH;
USE DATABASE COMMODITY_MARKET_PLATFORM;

CREATE OR REPLACE TABLE ANALYTICS.DIM_DATE AS
WITH date_spine AS (
    -- Generate every calendar day from 2011-01-01 through 2019-12-31
    SELECT DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1,
                   '2011-01-01'::DATE) AS CALENDAR_DATE
    FROM TABLE(GENERATOR(ROWCOUNT => 3287))   -- 9 years of days
)
SELECT
    CALENDAR_DATE,
    YEAR(CALENDAR_DATE)                                   AS YEAR,
    QUARTER(CALENDAR_DATE)                                AS QUARTER,
    MONTH(CALENDAR_DATE)                                  AS MONTH,
    MONTHNAME(CALENDAR_DATE)                              AS MONTH_NAME,
    DAY(CALENDAR_DATE)                                    AS DAY_OF_MONTH,
    DAYOFWEEK(CALENDAR_DATE)                              AS DAY_OF_WEEK,    -- 0=Sun..6=Sat
    DAYNAME(CALENDAR_DATE)                                AS DAY_NAME,
    WEEKOFYEAR(CALENDAR_DATE)                             AS WEEK_OF_YEAR,
    YEAR(CALENDAR_DATE) || '-Q' || QUARTER(CALENDAR_DATE) AS YEAR_QUARTER,
    TO_CHAR(CALENDAR_DATE, 'YYYY-MM')                     AS YEAR_MONTH,
    CASE WHEN DAYOFWEEK(CALENDAR_DATE) IN (0, 6)
         THEN FALSE ELSE TRUE END                         AS IS_WEEKDAY,
    -- Unique aspect: flag month-end / quarter-end for reporting cuts
    CASE WHEN CALENDAR_DATE = LAST_DAY(CALENDAR_DATE, 'MONTH')
         THEN TRUE ELSE FALSE END                         AS IS_MONTH_END,
    CASE WHEN CALENDAR_DATE = LAST_DAY(CALENDAR_DATE, 'QUARTER')
         THEN TRUE ELSE FALSE END                         AS IS_QUARTER_END
FROM date_spine;

-- Sanity check
SELECT MIN(CALENDAR_DATE) AS FIRST_DAY,
       MAX(CALENDAR_DATE) AS LAST_DAY,
       COUNT(*)           AS TOTAL_DAYS
FROM ANALYTICS.DIM_DATE;
