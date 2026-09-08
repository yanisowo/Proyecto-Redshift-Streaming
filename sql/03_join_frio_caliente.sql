-- El JOIN: datos calientes (Redshift, via Kinesis directo) 
-- contra datos frios (Iceberg, via Flink). 
-- Correr DESPUES de generar trafico con prueba_en_vivo.py
-- del mismo stream.

SELECT
    live.sensor_id,
    live.avg_temperature                          AS temperatura_actual,
    hist.avg_temperature                           AS promedio_historico,
    live.avg_temperature - hist.avg_temperature    AS desvio
FROM analytics_consumption.sensor_events_parsed live
JOIN lakehouse_iceberg.sensor_events hist
    ON live.sensor_id = hist.sensor_id
ORDER BY live.event_time DESC
LIMIT 20;
