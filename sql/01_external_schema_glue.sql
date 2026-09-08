-- Puente hacia el Glue Data Catalog que ya existe.
-- Reemplazar <cuenta> y el nombre del rol si lo cambiaste en Terraform.

CREATE EXTERNAL SCHEMA lakehouse_iceberg
FROM DATA CATALOG
DATABASE 'lakehouse_db'
IAM_ROLE 'arn:aws:iam::200015572841:role/dev-redshift-streaming-ingest-role'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- Verificacion rapida: deberian ver la tabla sensor_events
SELECT * 
FROM svv_external_tables 
WHERE schemaname = 'lakehouse_iceberg';
