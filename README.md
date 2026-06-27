# Commodity Market Intelligence Platform

A Snowflake-based data engineering project that turns raw commodity market data into clean, analytics-ready datasets, with automated pipelines, data quality auditing, and business-facing reporting views.

Built as part of a data engineering internship with London Success Academy and StoryPointsAI.

## What this project does

This project takes raw historical data on gold and oil prices, along with related macroeconomic indicators, and runs it through a layered ETL pipeline on Snowflake. The end result is a set of clean, validated fact tables and reporting views that can answer real business questions about commodity price behaviour, volatility, and macro correlations.

## Datasets used

| Dataset | Description | Source |
|---|---|---|
| `gold_stocks_price.csv` | Daily gold price (OHLCV), with embedded S&P 500, Dow Jones, USD Index, silver, platinum, palladium and gold/oil ETF series | Historical market data |
| `oil_price.csv` | Daily crude oil price (Open, High, Low, Close, Volume) | Historical market data |
| `DTWEXBGS.csv` | Trade Weighted US Dollar Index (Broad) | FRED (Federal Reserve Economic Data) |
| `VIXCLS.csv` | CBOE Volatility Index (VIX), a measure of market fear/uncertainty | FRED |
| `CPIAUCSL.csv` | US Consumer Price Index for All Urban Consumers, used as an inflation proxy | FRED |
| `SeriesExport.csv` | International energy production series across multiple countries | EIA (US Energy Information Administration) |

These datasets were combined to study not just commodity prices in isolation, but how gold and oil move in relation to equity markets, the US dollar, inflation, and market volatility.

## Architecture

The pipeline is built in Snowflake using a layered schema design:

- **RAW** – data loaded as-is from CSV source files, with file metadata and load timestamps preserved
- **STAGING** – cleaned and type-cast data, with bad dates, non-numeric values, negative prices and OHLC inconsistencies filtered out, and duplicates removed using window functions
- **ANALYTICS** – business-ready fact tables (`FACT_GOLD_MARKET`, `FACT_OIL_MARKET`) joined against a generated date dimension (`DIM_DATE`), with derived fields like daily range and percentage change
- **AUDIT** – a data quality log (`DQ_LOG`) tracking row counts, null checks, and validation issues with severity ratings

## Pipeline automation

Rather than relying on manual reruns, the pipeline uses Snowflake's native change data capture and orchestration features:

- **Streams** (`GOLD_RAW_STREAM`, `OIL_RAW_STREAM`) detect newly inserted rows in the raw tables
- **Tasks** are scheduled to run hourly, triggered only when a stream has new data (`SYSTEM$STREAM_HAS_DATA`)
- Tasks are chained, so the staging refresh automatically triggers a rebuild of the downstream analytics fact tables

## Data quality framework

A dedicated audit schema logs the health of the pipeline at each stage. Checks include total row counts, null or blank dates, and other validation rules, each logged with a severity rating (HIGH / MEDIUM / LOW) and a note explaining the finding. This makes data issues visible early rather than letting them surface silently in downstream reports.

## Analysis and hypothesis testing

On top of the clean fact tables, the project tests real business hypotheses directly in SQL, including:

- Whether oil is structurally more volatile than gold, using annualised volatility (standard deviation of daily returns, scaled by √252)
- Whether gold prices move inversely with the US Dollar Index, using correlation analysis
- Quarterly and annual price trends, trading ranges, and volume patterns

Exploratory analysis was also carried out in Python (Jupyter) to look for patterns ahead of writing the SQL hypothesis tests.

## Repository structure

```
SNOWFLAKE_ENV.sql              # Warehouse, database, and schema setup
DATA_LOADING.sql                # COPY INTO statements loading raw CSVs
STAGING.sql                     # Cleaning and casting logic, raw -> staging
DIM_DATE.sql                    # Generated calendar date dimension
DATA_AUGMENTATION.sql           # Fact table builds (staging -> analytics)
PIPELINE_AND_DASHBOARD.sql      # Streams, Tasks, and pipeline automation
UNIQUE_FEATURES.sql             # Stream + Task based incremental refresh
DATA_QUALITY_ANALYSIS.sql       # Audit log table and data quality checks
VALIDATION.sql                  # Row count, date range and null checks across layers
HYPOTHESIS_TESTING.sql          # Statistical hypothesis tests
BUSINESS_INSIGHT.sql            # Descriptive business insight queries
EXECUTIVE_INSIGHT_VIEWS.sql     # Reporting views for non-technical stakeholders
SAMPLE_QUERIES.sql              # Example queries against the analytics layer
Oil_Gold_EDA.ipynb              # Exploratory data analysis in Python
Deliverables/                   # Reports and presentation for the internship
```

## Tools and skills demonstrated

SQL, Snowflake (Streams, Tasks, warehouses, schemas), ETL pipeline design, data modelling, data quality auditing, Python (pandas, Jupyter), exploratory data analysis, hypothesis testing, statistical analysis, pipeline automation, technical documentation, agile collaboration.
