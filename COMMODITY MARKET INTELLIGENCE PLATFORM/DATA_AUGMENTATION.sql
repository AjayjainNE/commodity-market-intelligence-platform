USE WAREHOUSE COMMODITY_WH;
USE DATABASE COMMODITY_MARKET_PLATFORM;

CREATE OR REPLACE TABLE ANALYTICS.FACT_GOLD_MARKET AS
SELECT
    g.TRADE_DATE,
    d.YEAR,
    d.QUARTER,
    d.MONTH,
    d.MONTH_NAME,
    d.YEAR_QUARTER,
    d.YEAR_MONTH,
    d.IS_WEEKDAY,

    -- Core prices
    g.OPEN_PRICE,
    g.HIGH_PRICE,
    g.LOW_PRICE,
    g.CLOSE_PRICE,
    g.TRADE_VOLUME,
    ROUND(g.HIGH_PRICE - g.LOW_PRICE, 2) AS DAILY_RANGE,
    ROUND((g.CLOSE_PRICE - g.OPEN_PRICE) / NULLIF(g.OPEN_PRICE, 0) * 100, 4) AS PCT_CHANGE,

    -- Market indices
    g.SP500_INDEX,
    g.DOW_JONES_INDEX,
    g.USD_INDEX,
    g.GOLD_ETF_PRICE,
    g.OIL_ETF_PRICE,

    -- Augmentation: 7-day moving average of close price
    AVG(g.CLOSE_PRICE) OVER (
        ORDER BY g.TRADE_DATE
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS MA7_CLOSE,

    -- Augmentation: 30-day moving average
    AVG(g.CLOSE_PRICE) OVER (
        ORDER BY g.TRADE_DATE
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS MA30_CLOSE,

    -- Augmentation: 90-day moving average
    AVG(g.CLOSE_PRICE) OVER (
        ORDER BY g.TRADE_DATE
        ROWS BETWEEN 89 PRECEDING AND CURRENT ROW
    ) AS MA90_CLOSE,

    -- Augmentation: price lag (previous day close)
    LAG(g.CLOSE_PRICE, 1) OVER (
        ORDER BY g.TRADE_DATE
    ) AS PREV_DAY_CLOSE,

    -- Augmentation: day-over-day change
    g.CLOSE_PRICE - LAG(g.CLOSE_PRICE, 1) OVER (
        ORDER BY g.TRADE_DATE
    ) AS DOD_CHANGE,

    -- Augmentation: volatility (7-day rolling std dev)
    STDDEV(g.CLOSE_PRICE) OVER (
        ORDER BY g.TRADE_DATE
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS VOLATILITY_7D

FROM STAGING.STG_GOLD_MARKET g
LEFT JOIN ANALYTICS.DIM_DATE d
    ON g.TRADE_DATE = d.CALENDAR_DATE;

CREATE OR REPLACE TABLE ANALYTICS.FACT_OIL_MARKET AS
SELECT
    o.TRADE_DATE,
    d.YEAR,
    d.QUARTER,
    d.MONTH,
    d.MONTH_NAME,
    d.YEAR_QUARTER,
    d.YEAR_MONTH,
    d.IS_WEEKDAY,

    -- Core prices
    o.OPEN_PRICE,
    o.HIGH_PRICE,
    o.LOW_PRICE,
    o.CLOSE_PRICE,
    o.TRADE_VOLUME,
    ROUND(o.HIGH_PRICE - o.LOW_PRICE, 2) AS DAILY_RANGE,
    ROUND((o.CLOSE_PRICE - o.OPEN_PRICE) / NULLIF(o.OPEN_PRICE, 0) * 100, 4) AS PCT_CHANGE,

    -- Augmentation: 7-day moving average of close price
    AVG(o.CLOSE_PRICE) OVER (
        ORDER BY o.TRADE_DATE
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS MA7_CLOSE,

    -- Augmentation: 30-day moving average
    AVG(o.CLOSE_PRICE) OVER (
        ORDER BY o.TRADE_DATE
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS MA30_CLOSE,

    -- Augmentation: 90-day moving average
    AVG(o.CLOSE_PRICE) OVER (
        ORDER BY o.TRADE_DATE
        ROWS BETWEEN 89 PRECEDING AND CURRENT ROW
    ) AS MA90_CLOSE,

    -- Augmentation: price lag (previous day close)
    LAG(o.CLOSE_PRICE, 1) OVER (
        ORDER BY o.TRADE_DATE
    ) AS PREV_DAY_CLOSE,

    -- Augmentation: day-over-day change
    o.CLOSE_PRICE - LAG(o.CLOSE_PRICE, 1) OVER (
        ORDER BY o.TRADE_DATE
    ) AS DOD_CHANGE,

    -- Augmentation: volatility (7-day rolling std dev)
    STDDEV(o.CLOSE_PRICE) OVER (
        ORDER BY o.TRADE_DATE
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS VOLATILITY_7D

FROM STAGING.STG_OIL_MARKET o
LEFT JOIN ANALYTICS.DIM_DATE d
    ON o.TRADE_DATE = d.CALENDAR_DATE;



    
