USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

-- gold 

CREATE OR REPLACE TABLE RAW.GOLD_PRICES_RAW (
  trade_date STRING, open_price STRING, high_price STRING, low_price STRING,
  close_price STRING, volume STRING,
  _source_file STRING, _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  _run_id STRING DEFAULT NULL
);

COPY INTO RAW.GOLD_PRICES_RAW (trade_date, open_price, high_price, low_price, close_price, volume)
FROM @RAW.LANDING/gold/
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF')
ON_ERROR = 'CONTINUE';

UPDATE RAW.GOLD_PRICES_RAW SET _run_id = GETVARIABLE('run_id') WHERE _run_id IS NULL;

-- oil 

CREATE OR REPLACE TABLE RAW.OIL_PRICES_RAW (
  trade_date STRING, open_price STRING, high_price STRING, low_price STRING,
  close_price STRING, volume STRING,
  _source_file STRING, _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  _run_id STRING DEFAULT NULL
);

COPY INTO RAW.OIL_PRICES_RAW (trade_date, open_price, high_price, low_price, close_price, volume)
FROM @RAW.LANDING/oil/
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF')
ON_ERROR = 'CONTINUE';

UPDATE RAW.OIL_PRICES_RAW SET _run_id = GETVARIABLE('run_id') WHERE _run_id IS NULL;

-- dxy

CREATE OR REPLACE TABLE RAW.DXY_RAW (
  obs_date STRING, dxy_value STRING, _source_file STRING,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), _run_id STRING DEFAULT NULL
);

COPY INTO RAW.DXY_RAW (obs_date, dxy_value)
FROM @RAW.LANDING/dxy/
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF')
ON_ERROR = 'CONTINUE';

UPDATE RAW.DXY_RAW SET _run_id = GETVARIABLE('run_id') WHERE _run_id IS NULL;

-- cpi 

CREATE OR REPLACE TABLE RAW.CPI_RAW (
  obs_date STRING, cpi_value STRING, _source_file STRING,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), _run_id STRING DEFAULT NULL
);

COPY INTO RAW.CPI_RAW (obs_date, cpi_value)
FROM @RAW.LANDING/CPIAUCSL/
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF')
ON_ERROR = 'CONTINUE';

UPDATE RAW.CPI_RAW SET _run_id = GETVARIABLE('run_id') WHERE _run_id IS NULL;

-- vix 

CREATE OR REPLACE TABLE RAW.VIX_RAW (
  obs_date STRING, vix_value STRING, _source_file STRING,
  _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), _run_id STRING DEFAULT NULL
);

COPY INTO RAW.VIX_RAW (obs_date, vix_value)
FROM @RAW.LANDING/VIXCLS/
FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF')
ON_ERROR = 'CONTINUE';

UPDATE RAW.VIX_RAW SET _run_id = GETVARIABLE('run_id') WHERE _run_id IS NULL;

-- EIA 

CREATE OR REPLACE FILE FORMAT RAW.CSV_FF_RAWLINE
  TYPE='CSV' FIELD_DELIMITER='\u0001' RECORD_DELIMITER='\n'
  SKIP_HEADER=0 FIELD_OPTIONALLY_ENCLOSED_BY='"' TRIM_SPACE=TRUE;

CREATE OR REPLACE TABLE RAW.EIA_RAWLINES (ln NUMBER, line STRING);

COPY INTO RAW.EIA_RAWLINES (ln, line)
FROM (SELECT METADATA$FILE_ROW_NUMBER, $1
      FROM '@RAW.LANDING/the EIA SeriesExport file/')
FILE_FORMAT=(FORMAT_NAME='RAW.CSV_FF_RAWLINE')
ON_ERROR='CONTINUE';

-- parse annual

CREATE OR REPLACE TABLE CLEAN.EIA_OIL_ANNUAL AS
WITH cells AS (                       -- explode each line into positioned cells
  SELECT r.ln, s.index AS col, TRIM(s.value::STRING) AS cell
  FROM RAW.EIA_RAWLINES r,
       LATERAL SPLIT_TO_TABLE(r.line, ',') s
),
header AS (                           -- header = line with the most 4-digit years
  SELECT ln FROM cells
  WHERE cell RLIKE '^[0-9]{4}$'
  GROUP BY ln ORDER BY COUNT(*) DESC LIMIT 1
),
year_cols AS (                        -- column position -> year, read off the header
  SELECT c.col, TRY_TO_NUMBER(c.cell) AS yr
  FROM cells c JOIN header h ON c.ln = h.ln
  WHERE c.cell RLIKE '^[0-9]{4}$'
),
row_labels AS (                       -- each data row's text label (first non-numeric cell)
  SELECT c.ln, MIN_BY(c.cell, c.col) AS label
  FROM cells c
  WHERE c.cell <> '' AND NOT (c.cell RLIKE '^-?[0-9][0-9.,]*$')
  GROUP BY c.ln
)
SELECT yc.yr AS obs_year,
       TRY_TO_NUMBER(REPLACE(c.cell, ',', '')) AS world_production_mbd
FROM cells c
JOIN year_cols  yc ON c.col = yc.col
JOIN row_labels rl ON c.ln  = rl.ln
WHERE c.ln > (SELECT ln FROM header)            -- data rows only
  AND rl.label ILIKE '%World%'                  -- the World total row
  AND TRY_TO_NUMBER(REPLACE(c.cell, ',', '')) IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY yc.yr
        ORDER BY world_production_mbd DESC) = 1;


-- Verification

SELECT MIN(obs_year) AS first_yr, MAX(obs_year) AS last_yr,
       COUNT(*) AS yrs, ROUND(AVG(world_production_mbd),1) AS avg_world_mbd
FROM CLEAN.EIA_OIL_ANNUAL;

-- Audit : Log Loads

INSERT INTO AUDIT.RUN_LOG
  (run_id, run_started, step_no, layer, step_name, object_name,
   rows_in, rows_out, rows_dropped, status, message)
SELECT GETVARIABLE('run_id'), GETVARIABLE('run_started'), 1, 'RAW', 'ingest', d.obj, NULL, d.n, NULL,
       IFF(d.n>0,'OK','WARN'), IFF(d.n>0,'loaded','no rows — check stage path')
FROM (
  SELECT 'RAW.GOLD_PRICES_RAW' obj, COUNT(*) n FROM RAW.GOLD_PRICES_RAW
  UNION ALL SELECT 'RAW.OIL_PRICES_RAW', COUNT(*) FROM RAW.OIL_PRICES_RAW
  UNION ALL SELECT 'RAW.DXY_RAW',  COUNT(*) FROM RAW.DXY_RAW
  UNION ALL SELECT 'RAW.CPI_RAW',  COUNT(*) FROM RAW.CPI_RAW
  UNION ALL SELECT 'RAW.VIX_RAW',  COUNT(*) FROM RAW.VIX_RAW
  UNION ALL SELECT 'RAW.EIA_RAWLINES', COUNT(*) FROM RAW.EIA_RAWLINES
) d;

