USE WAREHOUSE INTEL_WH;
USE DATABASE COMMODITY_INTEL;

SET run_id = (SELECT UUID_STRING());
SET run_started = (SELECT CURRENT_TIMESTAMP());

CREATE OR REPLACE TABLE CLEAN.MARKET_EVENTS (
  event_date DATE, event_type STRING, description STRING
);
INSERT INTO CLEAN.MARKET_EVENTS VALUES
  ('2022-02-24','GEOPOLITICAL','Russia invades Ukraine — energy & safe-haven shock'),
  ('2022-03-16','MONETARY',    'Fed begins 2022 hiking cycle (first 25bp hike)'),
  ('2023-03-10','GEOPOLITICAL','SVB collapse / banking stress — flight to safety'),
  ('2023-04-02','OPEC',        'Surprise OPEC+ voluntary production cut announced'),
  ('2023-10-07','GEOPOLITICAL','Israel-Hamas conflict begins — Middle East risk premium'),
  ('2024-09-18','MONETARY',    'Fed begins 2024 cutting cycle (50bp cut)');