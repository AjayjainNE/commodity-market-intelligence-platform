USE WAREHOUSE COMMODITY_WH;
USE DATABASE COMMODITY_MARKET_PLATFORM;

--  1. STREAM + TASK : repeatable data ingestion process

CREATE OR REPLACE STREAM RAW.GOLD_RAW_STREAM
    ON TABLE RAW.RAW_GOLD_MARKET_DATA
    APPEND_ONLY = TRUE;

CREATE OR REPLACE TASK STAGING.TASK_REFRESH_GOLD_STAGING
    WAREHOUSE = COMMODITY_WH
    SCHEDULE  = '60 MINUTE'
WHEN SYSTEM$STREAM_HAS_DATA('RAW.GOLD_RAW_STREAM')
AS
    MERGE INTO STAGING.STG_GOLD_MARKET t
    USING (
        SELECT
            TRY_TO_DATE(DATE)                        AS TRADE_DATE,
            TRY_TO_DOUBLE(OPEN)                      AS OPEN_PRICE,
            TRY_TO_DOUBLE(HIGH)                      AS HIGH_PRICE,
            TRY_TO_DOUBLE(LOW)                       AS LOW_PRICE,
            TRY_TO_DOUBLE(CLOSE)                     AS CLOSE_PRICE,
            TRY_TO_NUMBER(REPLACE(VOLUME, ',', ''))  AS TRADE_VOLUME,
            TRY_TO_DOUBLE(SP500)                     AS SP500_INDEX,
            TRY_TO_DOUBLE(DOW_JONES)                 AS DOW_JONES_INDEX,
            TRY_TO_DOUBLE(USD_INDEX)                 AS USD_INDEX,
            TRY_TO_DOUBLE(GOLD_ETF)                  AS GOLD_ETF_PRICE,
            TRY_TO_DOUBLE(OIL_ETF)                   AS OIL_ETF_PRICE,
            _LOADED_AT,
            _FILE_NAME
        FROM RAW.GOLD_RAW_STREAM
        WHERE TRY_TO_DATE(DATE) IS NOT NULL
          AND TRY_TO_DOUBLE(CLOSE) > 0
          AND TRY_TO_DOUBLE(LOW) <= TRY_TO_DOUBLE(HIGH)
    ) s
    ON t.TRADE_DATE = s.TRADE_DATE
    WHEN MATCHED THEN UPDATE SET
        t.OPEN_PRICE = s.OPEN_PRICE,  t.HIGH_PRICE  = s.HIGH_PRICE,
        t.LOW_PRICE  = s.LOW_PRICE,   t.CLOSE_PRICE = s.CLOSE_PRICE,
        t.TRADE_VOLUME = s.TRADE_VOLUME, t._LOADED_AT = s._LOADED_AT
    WHEN NOT MATCHED THEN INSERT (
        TRADE_DATE, OPEN_PRICE, HIGH_PRICE, LOW_PRICE, CLOSE_PRICE,
        TRADE_VOLUME, SP500_INDEX, DOW_JONES_INDEX, USD_INDEX,
        GOLD_ETF_PRICE, OIL_ETF_PRICE, _LOADED_AT, _FILE_NAME)
    VALUES (
        s.TRADE_DATE, s.OPEN_PRICE, s.HIGH_PRICE, s.LOW_PRICE, s.CLOSE_PRICE,
        s.TRADE_VOLUME, s.SP500_INDEX, s.DOW_JONES_INDEX, s.USD_INDEX,
        s.GOLD_ETF_PRICE, s.OIL_ETF_PRICE, s._LOADED_AT, s._FILE_NAME);

ALTER TASK STAGING.TASK_REFRESH_GOLD_STAGING RESUME;

-- 2. STORED PROCEDURE : one-call data quality run

CREATE OR REPLACE PROCEDURE AUDIT.SP_RUN_DQ_CHECKS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    INSERT INTO AUDIT.DQ_LOG (
        TABLE_NAME,
        CHECK_NAME,
        ISSUE_COUNT,
        TOTAL_ROWS,
        PCT_AFFECTED,
        SEVERITY,
        NOTES
    )
    SELECT
        'RAW_GOLD_MARKET_DATA',
        'NULL_OR_BLANK_DATE',
        SUM(
            CASE
                WHEN "DATE" IS NULL
                     OR TRIM("DATE") = ''
                THEN 1
                ELSE 0
            END
        ),
        COUNT(*),
        ROUND(
            100.0 * SUM(
                CASE
                    WHEN "DATE" IS NULL
                         OR TRIM("DATE") = ''
                    THEN 1
                    ELSE 0
                END
            ) / NULLIF(COUNT(*), 0),
            2
        ),
        CASE
            WHEN SUM(
                CASE
                    WHEN "DATE" IS NULL
                         OR TRIM("DATE") = ''
                    THEN 1
                    ELSE 0
                END
            ) > 0
            THEN 'HIGH'
            ELSE 'LOW'
        END,
        'Scheduled re-run via stored procedure'
    FROM RAW.RAW_GOLD_MARKET_DATA;

    INSERT INTO AUDIT.DQ_LOG (
        TABLE_NAME,
        CHECK_NAME,
        ISSUE_COUNT,
        TOTAL_ROWS,
        PCT_AFFECTED,
        SEVERITY,
        NOTES
    )
    SELECT
        'RAW_GOLD_MARKET_DATA',
        'NON_POSITIVE_CLOSE_PRICE',
        SUM(
            CASE
                WHEN TRY_TO_DOUBLE(CLOSE) <= 0
                THEN 1
                ELSE 0
            END
        ),
        COUNT(*),
        ROUND(
            100.0 * SUM(
                CASE
                    WHEN TRY_TO_DOUBLE(CLOSE) <= 0
                    THEN 1
                    ELSE 0
                END
            ) / NULLIF(COUNT(*), 0),
            2
        ),
        CASE
            WHEN SUM(
                CASE
                    WHEN TRY_TO_DOUBLE(CLOSE) <= 0
                    THEN 1
                    ELSE 0
                END
            ) > 0
            THEN 'HIGH'
            ELSE 'LOW'
        END,
        'Scheduled re-run via stored procedure'
    FROM RAW.RAW_GOLD_MARKET_DATA;

    RETURN 'DQ checks completed at ' || CURRENT_TIMESTAMP();

END;
$$;

--3. TIME TRAVEL + ZERO-COPY CLONE : Snowflake's signature features.

SELECT COUNT(*) AS ROWS_5_MIN_AGO
FROM STAGING.STG_GOLD_MARKET AT(OFFSET => -300);

CREATE OR REPLACE TABLE STAGING.STG_GOLD_MARKET_DEV
CLONE STAGING.STG_GOLD_MARKET;

-- 4. INSIGHT VIEW : Gold vs Oil correlation by year

CREATE OR REPLACE VIEW ANALYTICS.VW_GOLD_OIL_CORRELATION AS

SELECT
    g.YEAR,
    COUNT(*) AS PAIRED_DAYS,
    ROUND(CORR(g.CLOSE_PRICE, o.CLOSE_PRICE), 3) AS PRICE_CORRELATION,
    ROUND(CORR(g.PCT_CHANGE, o.PCT_CHANGE), 3) AS DAILY_RETURN_CORRELATION,
    CASE
        WHEN CORR(g.PCT_CHANGE, o.PCT_CHANGE) > 0.5 THEN 'STRONG POSITIVE'
        WHEN CORR(g.PCT_CHANGE, o.PCT_CHANGE) > 0.2 THEN 'MODERATE POSITIVE'
        WHEN CORR(g.PCT_CHANGE, o.PCT_CHANGE) < -0.2 THEN 'NEGATIVE'
        ELSE 'WEAK / NONE'
    END AS RELATIONSHIP
FROM ANALYTICS.FACT_GOLD_MARKET g
JOIN ANALYTICS.FACT_OIL_MARKET o
    ON g.TRADE_DATE = o.TRADE_DATE
GROUP BY g.YEAR;

-- 5. INSIGHT VIEW : Golden Cross / Death Cross trading signals

CREATE OR REPLACE VIEW ANALYTICS.VW_GOLD_MA_CROSS_SIGNALS AS

WITH ma AS (
    SELECT
        TRADE_DATE,
        CLOSE_PRICE,
        MA7_CLOSE,
        MA30_CLOSE,
        LAG(MA7_CLOSE) OVER (ORDER BY TRADE_DATE) AS PREV_MA7,
        LAG(MA30_CLOSE) OVER (ORDER BY TRADE_DATE) AS PREV_MA30
    FROM ANALYTICS.FACT_GOLD_MARKET
)

SELECT
    TRADE_DATE,
    CLOSE_PRICE,
    ROUND(MA7_CLOSE, 2) AS MA7,
    ROUND(MA30_CLOSE, 2) AS MA30,
    CASE
        WHEN PREV_MA7 <= PREV_MA30
             AND MA7_CLOSE > MA30_CLOSE
        THEN 'GOLDEN_CROSS (bullish)'

        WHEN PREV_MA7 >= PREV_MA30
             AND MA7_CLOSE < MA30_CLOSE
        THEN 'DEATH_CROSS (bearish)'
    END AS SIGNAL
FROM ma
WHERE SIGNAL IS NOT NULL
ORDER BY TRADE_DATE;


-- 6. INSIGHT VIEW : Maximum drawdown

CREATE OR REPLACE VIEW ANALYTICS.VW_GOLD_DRAWDOWN AS

WITH peaks AS (
    SELECT
        TRADE_DATE,
        CLOSE_PRICE,
        MAX(CLOSE_PRICE) OVER (
            ORDER BY TRADE_DATE
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS RUNNING_PEAK
    FROM ANALYTICS.FACT_GOLD_MARKET
)

SELECT
    TRADE_DATE,
    CLOSE_PRICE,
    RUNNING_PEAK,
    ROUND(
        (CLOSE_PRICE - RUNNING_PEAK)
        / NULLIF(RUNNING_PEAK, 0) * 100,
        2
    ) AS DRAWDOWN_PCT
FROM peaks;

