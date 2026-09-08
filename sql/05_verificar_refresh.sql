-- Diagnostico: por que fallo (o no) el ultimo refresh de la MV.

SELECT
    database_name,
    schema_name,
    name,
    is_stale,
    state,
    autorefresh,
    autorewrite
FROM SVV_MV_INFO
WHERE name = 'sensor_events_live';

-- Si el lag crece de forma sostenida (MillisBehindLatest en
-- CloudWatch), es Consumer Lag: escalar shards de Kinesis o el
-- base_capacity del workgroup de Redshift.
