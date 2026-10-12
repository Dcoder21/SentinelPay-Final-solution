data "aws_caller_identity" "current" {}

# =========================================================
# RANDOM SUFFIXES
# =========================================================

resource "random_id" "trail_suffix" {
  byte_length = 4
}

resource "random_id" "access_logs_suffix" {
  byte_length = 4
}

# =========================================================
# S3 ACCESS LOG DESTINATION BUCKET
# =========================================================
# This bucket receives S3 server access logs from the
# CloudTrail bucket.
#
# AWS requires S3 server access-log destination buckets to
# use SSE-S3 rather than SSE-KMS.
# =========================================================
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "access_logs" { #tfsec:ignore:aws-s3-enable-bucket-logging
  # This bucket is the destination for S3 server access logs.
  # Enabling access logging on this bucket would create recursive logging.

  # checkov:skip=CKV_AWS_18:This bucket is the destination for S3 server access logs and must not log to itself
  # checkov:skip=CKV_AWS_145:S3 server access log destination buckets require SSE-S3 rather than SSE-KMS
  # checkov:skip=CKV2_AWS_62:Event notifications are not required for the dedicated S3 access-log destination bucket
  # checkov:skip=CKV_AWS_144:Cross-region replication is intentionally not enabled for the development access-log bucket

  bucket = "${var.project_name}-${var.environment}-s3-access-logs-${random_id.access_logs_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-s3-access-logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}
# =========================================================
# S3 ACCESS LOG BUCKET ENCRYPTION
# =========================================================
# This bucket is dedicated to S3 server access logs.
# SSE-S3 (AES256) is intentionally used instead of SSE-KMS.
# Using SSE-KMS for an S3 server-access-log destination can
# interfere with log delivery, so this exception is intentional.
# =========================================================

#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  # checkov:skip=CKV_AWS_145:S3 server access log destination buckets require SSE-S3 rather than SSE-KMS

  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "access-log-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.access_logs
  ]
}

data "aws_iam_policy_document" "access_logs_bucket" {
  statement {
    sid    = "AllowConfigBucketAccessLogs"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "logging.s3.amazonaws.com"
      ]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.access_logs.arn}/config-access-logs/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"

      values = [
        aws_s3_bucket.config.arn
      ]
    }
  }
}
resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  policy = data.aws_iam_policy_document.access_logs_bucket.json

  depends_on = [
    aws_s3_bucket_public_access_block.access_logs,
    aws_s3_bucket_ownership_controls.access_logs
  ]
}

# =========================================================
# CLOUDTRAIL S3 BUCKET
# =========================================================

resource "aws_s3_bucket" "cloudtrail" {
  # checkov:skip=CKV_AWS_144:Cross-region replication is intentionally not enabled in development; production disaster-recovery replication is managed separately

  bucket = "${var.project_name}-${var.environment}-cloudtrail-${random_id.trail_suffix.hex}"

  object_lock_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-cloudtrail"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =========================================================
# VERSIONING
# Required for S3 Object Lock
# =========================================================

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =========================================================
# OBJECT LOCK
# =========================================================

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.cloudtrail_retention_days
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.cloudtrail
  ]
}

# =========================================================
# PUBLIC ACCESS BLOCK
# =========================================================

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =========================================================
# CLOUDTRAIL BUCKET ENCRYPTION
# =========================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = true
  }
}

# =========================================================
# S3 SERVER ACCESS LOGGING
# CKV_AWS_18
# =========================================================

resource "aws_s3_bucket_logging" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "cloudtrail-access-logs/"

  depends_on = [
    aws_s3_bucket_policy.access_logs
  ]
}

# =========================================================
# S3 LIFECYCLE CONFIGURATION
# CKV2_AWS_61
#
# We avoid normal object expiration here because CloudTrail
# objects are protected by Object Lock COMPLIANCE retention.
# =========================================================

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-lifecycle"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.cloudtrail,
    aws_s3_bucket_object_lock_configuration.cloudtrail
  ]
}

# =========================================================
# EVENT NOTIFICATIONS
# CKV2_AWS_62
# =========================================================

resource "aws_s3_bucket_notification" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  eventbridge = true
}

# =========================================================
# CLOUDTRAIL BUCKET POLICY
# =========================================================

data "aws_iam_policy_document" "cloudtrail_bucket" {

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudtrail.amazonaws.com"
      ]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      aws_s3_bucket.cloudtrail.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudtrail.amazonaws.com"
      ]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
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
      variable = "aws:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type = "*"

      identifiers = [
        "*"
      ]
    }

    actions = [
      "s3:*"
    ]

    resources = [
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = [
        "false"
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = data.aws_iam_policy_document.cloudtrail_bucket.json

  depends_on = [
    aws_s3_bucket_public_access_block.cloudtrail
  ]
}

# =========================================================
# SNS TOPIC
# =========================================================

resource "aws_sns_topic" "cloudtrail" {
  name = "${var.project_name}-${var.environment}-cloudtrail-notifications"

  kms_master_key_id = var.kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-cloudtrail-notifications"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =========================================================
# SNS TOPIC POLICY
# Allow CloudTrail to publish notifications
# =========================================================

data "aws_iam_policy_document" "cloudtrail_sns" {

  statement {
    sid    = "AllowCloudTrailPublish"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudtrail.amazonaws.com"
      ]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [
      aws_sns_topic.cloudtrail.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }
}

resource "aws_sns_topic_policy" "cloudtrail" {
  arn = aws_sns_topic.cloudtrail.arn

  policy = data.aws_iam_policy_document.cloudtrail_sns.json
}

# =========================================================
# CLOUDWATCH LOG GROUP
# =========================================================

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}-${var.environment}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-cloudtrail"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =========================================================
# CLOUDTRAIL CLOUDWATCH IAM ROLE
# =========================================================

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-${var.environment}-cloudtrail-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowCloudTrailAssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-cloudtrail-cloudwatch"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =========================================================
# CLOUDTRAIL CLOUDWATCH IAM POLICY
# =========================================================

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-${var.environment}-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    #tfsec:ignore:aws-iam-no-policy-wildcards
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "CloudTrailWriteLogs"
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}
# =========================================================
# CLOUDTRAIL
# =========================================================

resource "aws_cloudtrail" "this" {
  name = "${var.project_name}-${var.environment}-trail"

  s3_bucket_name = aws_s3_bucket.cloudtrail.bucket

  kms_key_id = var.kms_key_arn

  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  # CloudTrail expects the SNS topic name here.
  sns_topic_name = aws_sns_topic.cloudtrail.name

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_s3_bucket_object_lock_configuration.cloudtrail,
    aws_s3_bucket_logging.cloudtrail,
    aws_s3_bucket_lifecycle_configuration.cloudtrail,
    aws_s3_bucket_notification.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch,
    aws_sns_topic_policy.cloudtrail
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-trail"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}