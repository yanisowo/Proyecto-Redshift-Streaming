-- Aplicar el principio de minimo privilegio dentro de SQL, 
-- igual que ya vienen aplicando en IAM.

-- Nadie toca el esquema crudo directamente
REVOKE ALL ON SCHEMA kinesis_raw FROM PUBLIC;

-- Los analistas solo ven la capa ya transformada
CREATE GROUP power_users;

GRANT USAGE ON SCHEMA analytics_consumption TO GROUP power_users;

GRANT SELECT ON analytics_consumption.sensor_events_parsed TO GROUP power_users;
