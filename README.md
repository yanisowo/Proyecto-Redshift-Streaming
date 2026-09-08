# UrbanAir – Streaming Lakehouse con Redshift

## 1. Descripción general

Este proyecto implementa una arquitectura de datos en streaming sobre AWS.

El flujo principal recibe eventos desde Amazon Kinesis y los procesa en paralelo mediante dos caminos:

- Apache Flink persiste los datos históricos en Apache Iceberg sobre Amazon S3.
- Amazon Redshift Serverless consume directamente el mismo stream de Kinesis para análisis de baja latencia.

Finalmente, Redshift combina los datos calientes provenientes de Kinesis con los datos históricos almacenados en Iceberg.

---

## 2. Arquitectura

```text
                         ┌─────────────────────┐
                         │   Generador Python  │
                         │ prueba_en_vivo.py   │
                         └──────────┬──────────┘
                                    │
                                    ▼
                         ┌─────────────────────┐
                         │   Amazon Kinesis    │
                         │ dev-events-stream   │
                         └──────────┬──────────┘
                                    │
                       ┌────────────┴────────────┐
                       │                         │
                       ▼                         ▼
             ┌──────────────────┐      ┌──────────────────────┐
             │ Managed Flink    │      │ Redshift Serverless  │
             │                  │      │ Streaming Ingestion  │
             └────────┬─────────┘      └──────────┬───────────┘
                      │                           │
                      ▼                           ▼
             ┌──────────────────┐       sensor_events_live
             │ Apache Iceberg   │       Materialized View
             └────────┬─────────┘                  │
                      │                            ▼
                      ▼                 analytics_consumption
             ┌──────────────────┐                  │
             │ Amazon S3        │                  │
             │ Data Lake        │                  │
             └────────┬─────────┘                  │
                      │                            │
                      ▼                            │
             ┌──────────────────┐                  │
             │ AWS Glue Catalog │                  │
             └────────┬─────────┘                  │
                      │                            │
                      └──────────────┬─────────────┘
                                     ▼
                            JOIN frío + caliente

```
---

## 3. Servicios utilizados

**Amazon Kinesis Data Streams**

Recibe los eventos generados por `prueba_en_vivo.py`.

Stream utilizado:
```text
dev-events-stream
```
**Amazon Managed Service for Apache Flink**

Procesa los eventos del stream y persiste el histórico en Apache Iceberg.

Aplicación:
```text
dev-lakehouse-flink-job
```
**Amazon S3**

Almacena:

- datos históricos;
- metadata y archivos de Iceberg;
- artefacto JAR de Flink.


**AWS Glue Data Catalog**

Mantiene el catálogo de las tablas Iceberg.

Base de datos:
```text
lakehouse_db
```
**Amazon Redshift Serverless**

Funciona como capa analítica para:

- Streaming Ingestion desde Kinesis;
- consultas de baja latencia;
- lectura de Iceberg;
- JOIN entre datos calientes e históricos.

Namespace:
```text
dev-lakehouse-ns
```
Workgroup:
```text
dev-lakehouse-wg
```
---

## 4. Formato de eventos
Los eventos generados durante la prueba utilizan texto plano separado por coma:
```text
sensor-4,30.79
```
donde: 
```text
sensor-4 → sensor_id
30.79    → avg_temperature
```
Por este motivo, Redshift utiliza `SPLIT_PART` para transformar cada evento en columnas.
---

## 5. Flujo de datos
**Flujo histórico**
```text
Python
  ↓
Kinesis
  ↓
Flink
  ↓
Apache Iceberg
  ↓
S3
  ↓
Glue Data Catalog
```
**Flujo de baja latencia**
```text
Python
  ↓
Kinesis
  ↓
Redshift Streaming Ingestion
  ↓
sensor_events_live
  ↓
analytics_consumption.sensor_events_parsed
```
---

## 6. Redshift Streaming Ingestion

Redshift consume directamente el mismo stream de Kinesis utilizado por Flink.

Se crea primero el esquema externo:
```sql
CREATE EXTERNAL SCHEMA kinesis_raw
FROM KINESIS
IAM_ROLE 'arn:aws:iam::<ACCOUNT_ID>:role/dev-redshift-streaming-ingest-role';
```
Luego se crea la Materialized View:
```sql
CREATE MATERIALIZED VIEW sensor_events_live
AUTO REFRESH YES
AS
SELECT
    approximate_arrival_timestamp,
    partition_key,
    SPLIT_PART(
        from_varbyte(kinesis_data, 'utf-8'),
        ',',
        1
    ) AS sensor_id,
    SPLIT_PART(
        from_varbyte(kinesis_data, 'utf-8'),
        ',',
        2
    )::float AS avg_temperature
FROM kinesis_raw."dev-events-stream";
```
---

## 7. Capa de consumo analítico
Para evitar que los consumidores consulten directamente el esquema crudo de Kinesis, se creó:
```text
analytics_consumption
```
y la vista:
```text
analytics_consumption.sensor_events_parsed
```
SQL:
```sql
CREATE OR REPLACE VIEW analytics_consumption.sensor_events_parsed AS
SELECT
    approximate_arrival_timestamp AS event_time,
    sensor_id,
    avg_temperature
FROM sensor_events_live;
```
---

## 8. Integración con Iceberg

Redshift se conecta al Glue Data Catalog mediante:
```sql
CREATE EXTERNAL SCHEMA lakehouse_iceberg
FROM DATA CATALOG
DATABASE 'lakehouse_db'
IAM_ROLE 'arn:aws:iam::<ACCOUNT_ID>:role/dev-redshift-streaming-ingest-role'
CREATE EXTERNAL DATABASE IF NOT EXISTS;
```
Esto permite consultar:
```text
lakehouse_iceberg.sensor_events
```
directamente desde Redshift.
---

## 9. JOIN frío + caliente

La consulta final combina:

- datos recientes de Kinesis;
- datos históricos de Iceberg.

```sql
SELECT
    live.sensor_id,
    live.avg_temperature AS temperatura_actual,
    hist.avg_temperature AS promedio_historico,
    live.avg_temperature - hist.avg_temperature AS desvio
FROM analytics_consumption.sensor_events_parsed live
JOIN lakehouse_iceberg.sensor_events hist
    ON live.sensor_id = hist.sensor_id
ORDER BY live.event_time DESC
LIMIT 20;
```
Este JOIN permite comparar el valor reciente de cada sensor con los valores históricos persistidos.
---

## 10. Seguridad

Redshift utiliza un rol IAM independiente del utilizado por Flink.

Permisos principales:
```text
Kinesis
- DescribeStream
- GetShardIterator
- GetRecords
- ListShards

KMS
- Decrypt

Glue
- GetDatabase
- GetTable
- GetPartitions

S3
- GetObject
- GetObjectVersion
- ListBucket
- GetBucketLocation
```
Además, se aplicó RBAC dentro de Redshift:
```sql
REVOKE ALL ON SCHEMA kinesis_raw FROM PUBLIC;

CREATE GROUP power_users;

GRANT USAGE
ON SCHEMA analytics_consumption
TO GROUP power_users;

GRANT SELECT
ON analytics_consumption.sensor_events_parsed
TO GROUP power_users;
```
---

## 11. Verificación de la Materialized View

Se utilizó:
```sql
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
```
La configuración mostró:
```text
autorefresh = true
```
Además, durante las pruebas el conteo aumentó progresivamente:
```text
50
100
150
```
confirmando que nuevos eventos fueron incorporados desde Kinesis.
---

## 12. Prueba en vivo

Variables requeridas:
```powershell
$env:KINESIS_STREAM_NAME="dev-events-stream"
$env:AWS_REGION="us-east-1"
```
Ejecución:
```powershell
python prueba_en_vivo.py
```
Verificación:
```sql
SELECT COUNT(*)
FROM sensor_events_live;
```
---

## 13. Estructura del proyecto
```text
semana-6/
│
├── bootstrap/
├── environments/
│   └── dev/
├── flink-app/
├── modules/
│   ├── identity/
│   ├── ingestion/
│   └── network/
├── sql/
├── test/
├── screenshots/
├── README.md
└── .gitignore
```
---

## 14. Despliegue
Crear backend Terraform
```powershell
bash ./bootstrap/bootstrap-backend.sh urbanair-2026
```
Inicializar Terraform
```powershell
terraform init
terraform validate
terraform plan
```
Compilar Flink
```powershell
cd flink-app
mvn clean package
```
Subir JAR
```powershell
aws s3 cp `
  ".\target\lakehouse-streaming-job.jar" `
  "s3://<DATALAKE_BUCKET>/flink-artifacts/lakehouse-streaming-job.jar"
```
Desplegar infraestructura
```powershell
terraform apply
```
---

## 15. Limpieza

Para detener Flink:
```powershell
aws kinesisanalyticsv2 stop-application `
  --application-name dev-lakehouse-flink-job `
  --force `
  --region us-east-1
```
Al finalizar completamente el checkpoint:
```powershell
terraform destroy
```
Antes del `destroy`, vaciar el bucket S3 si Terraform no puede eliminarlo por contener objetos.