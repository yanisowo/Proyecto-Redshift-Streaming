# ── Módulo de identidad ────────────────────────────────
# Rol único que se reusa a lo largo de todo el curso: lo consume el
# job de Flink, y se le agregan permisos de Glue.

data "aws_iam_policy_document" "flink_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flink_execution_role" {
  name               = "${var.environment}-flink-execution-role"
  assume_role_policy = data.aws_iam_policy_document.flink_assume_role.json
}

# Permisos base: solo lo que Flink necesita para leer/escribir en el
# prefijo del data lake y consumir Kinesis. Nada de "*".
data "aws_iam_policy_document" "flink_base_permissions" {

  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      var.datalake_bucket_arn
    ]
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion"
    ]

    resources = [
      "${var.datalake_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "KinesisConsume"
    effect = "Allow"

    actions = [
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard"
    ]

    resources = [
      var.kinesis_stream_arn
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flink_base" {
  name   = "${var.environment}-flink-base-permissions"
  role   = aws_iam_role.flink_execution_role.id
  policy = data.aws_iam_policy_document.flink_base_permissions.json
}

# Rol de solo lectura para auditoría
data "aws_iam_policy_document" "audit_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id != "" ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" : ""]
    }
  }
}

resource "aws_iam_role" "audit_readonly" {
  name               = "${var.environment}-audit-readonly"
  assume_role_policy = data.aws_iam_policy_document.audit_assume_role.json
}

resource "aws_iam_role_policy_attachment" "audit_readonly_attach" {
  role       = aws_iam_role.audit_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_caller_identity" "current" {}
