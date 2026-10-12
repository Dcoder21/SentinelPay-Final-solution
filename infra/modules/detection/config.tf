resource "aws_iam_role" "config" {
  name = "${var.project_name}-${var.environment}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "config.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role = aws_iam_role.config.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}
resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project_name}-${var.environment}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}
resource "random_id" "config_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "config" {
  # checkov:skip=CKV_AWS_144:Cross-region replication is intentionally not enabled in development; production disaster-recovery replication is managed separately
  bucket = "${var.project_name}-${var.environment}-config-${random_id.config_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-config"
    Environment = var.environment
  }
}
# ---------------------------------------------------------
# AWS Config S3 Access Logging
# CKV_AWS_18
# ---------------------------------------------------------

resource "aws_s3_bucket_logging" "config" {
  bucket = aws_s3_bucket.config.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "config-access-logs/"

  depends_on = [
    aws_s3_bucket_policy.access_logs
  ]
}
data "aws_iam_policy_document" "config_bucket" {

  # AWS Config checks whether it can access the bucket.
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "config.amazonaws.com"
      ]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      aws_s3_bucket.config.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }

  # Allow Config to list the bucket.
  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "config.amazonaws.com"
      ]
    }

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.config.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }

  # Allow AWS Config to deliver configuration data.
  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "config.amazonaws.com"
      ]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"

      values = [
        "bucket-owner-full-control"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = data.aws_iam_policy_document.config_bucket.json
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}
resource "aws_config_delivery_channel" "this" {
  name = "${var.project_name}-${var.environment}-config-delivery"

  s3_bucket_name = aws_s3_bucket.config.bucket

  s3_kms_key_arn = var.kms_key_arn

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config
  ]
}
resource "aws_config_configuration_recorder_status" "this" {
  name = aws_config_configuration_recorder.this.name

  is_enabled = true

  depends_on = [
    aws_config_delivery_channel.this
  ]
}
resource "aws_config_conformance_pack" "cis" {
  name = "${var.project_name}-${var.environment}-cis"

  template_body = file(
    "${path.module}/config/cis-aws-v1.4-level2.yaml"
  )

  depends_on = [
    aws_config_configuration_recorder_status.this
  ]
}
resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "config-retention"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.config
  ]
}

resource "aws_s3_bucket_notification" "config" {
  bucket      = aws_s3_bucket.config.id
  eventbridge = true
}