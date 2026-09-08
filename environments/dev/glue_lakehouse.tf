# ============================================================
# AWS Glue Data Catalog - UrbanAir Lakehouse
# ============================================================

resource "aws_glue_catalog_database" "lakehouse_db" {
  name        = "lakehouse_db"
  description = "Metastore central para las tablas Iceberg del pipeline de streaming"
}

# ============================================================
# Permisos Flink -> AWS Glue + S3
# ============================================================
data "aws_iam_policy_document" "flink_glue_access" {
  statement {
    sid    = "GlueCatalogAccess"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetPartitions",
      "glue:CreatePartition",
      "glue:BatchCreatePartition"
    ]

    resources = [
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.lakehouse_db.name}",
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.lakehouse_db.name}/*"
    ]
  }

  statement {
    sid    = "LakehouseS3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      module.network.datalake_bucket_arn
    ]
  }

  statement {
    sid    = "LakehouseS3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${module.network.datalake_bucket_arn}/lakehouse/*"
    ]
  }
}

# ============================================================
# Adjuntar permisos adicionales al rol de ejecución de Flink
# ============================================================
resource "aws_iam_role_policy" "flink_glue_policy" {
  name   = "flink-glue-lakehouse-access"
  role   = module.identity.flink_execution_role_name
  policy = data.aws_iam_policy_document.flink_glue_access.json
}

# ============================================================
# Información de la cuenta AWS
# ============================================================
data "aws_caller_identity" "current" {}

# ============================================================
# Outputs
# ============================================================
output "lakehouse_db_name" {
  value = aws_glue_catalog_database.lakehouse_db.name
}

output "lakehouse_table_path" {
  value = "s3://${module.network.datalake_bucket_name}/lakehouse/events/"
}

output "datalake_bucket_name" {
  value = module.network.datalake_bucket_name
}

output "kinesis_stream_name" {
  value = module.ingestion.kinesis_stream_name
}

output "flink_app_name" {
  value = aws_kinesisanalyticsv2_application.flink_job.name
}