# ---------------------------------------------------------
# Random suffix for globally unique bucket names
# ---------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ---------------------------------------------------------
# Account-wide S3 Public Access Block
# ---------------------------------------------------------

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =========================================================
# S3 ACCESS LOG BUCKET
# =========================================================

resource "aws_s3_bucket" "access_logs" { #tfsec:ignore:aws-s3-enable-bucket-logging
  # checkov:skip=CKV_AWS_145:S3 server access log destination uses SSE-S3 for reliable service delivery
  # checkov:skip=CKV_AWS_144:Cross-region replication is intentionally not enabled in the development environment; production DR replication is managed separately
  # checkov:skip=CKV_AWS_18:This bucket is the destination for S3 server access logs and must not log to itself

  bucket = "${var.project_name}-${var.environment}-s3-access-logs-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-s3-access-logs"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# Public Access Block
# ---------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------
# Access Log Bucket Versioning
# CKV_AWS_21
# ---------------------------------------------------------

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------
# S3 server access log destination uses SSE-S3 for service compatibility.
# ---------------------------------------------------------

# tfsec:ignore:aws-s3-encryption-customer-key S3 access log destination uses SSE-S3.
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  # checkov:skip=CKV_AWS_145:S3 server access log destination uses SSE-S3 for reliable service delivery
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

  }
}

# ---------------------------------------------------------
# Access Log Bucket Lifecycle
#
# CKV2_AWS_61
# CKV_AWS_300
# ---------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  depends_on = [
    aws_s3_bucket_versioning.access_logs
  ]

  rule {
    id     = "access-log-retention"
    status = "Enabled"

    filter {}

    # Abort incomplete multipart uploads after 7 days.
    # Fixes CKV_AWS_300.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    expiration {
      days = 365
    }
  }
}

# ---------------------------------------------------------
# Access Log Bucket Event Notifications
# CKV2_AWS_62
# ---------------------------------------------------------

resource "aws_s3_bucket_notification" "access_logs" {
  bucket      = aws_s3_bucket.access_logs.id
  eventbridge = true
}

# =========================================================
# KYC DOCUMENT BUCKET
# =========================================================

resource "aws_s3_bucket" "kyc" {
  # checkov:skip=CKV_AWS_144:Cross-region replication is intentionally not enabled in the development environment; production DR replication is managed separately

  bucket = "${var.project_name}-${var.environment}-kyc-${random_id.bucket_suffix.hex}"

  object_lock_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-kyc"
    Environment = var.environment
    DataClass   = "KYC"
  }
}

# ---------------------------------------------------------
# KYC Versioning
# Required for S3 Object Lock
# ---------------------------------------------------------

resource "aws_s3_bucket_versioning" "kyc" {
  bucket = aws_s3_bucket.kyc.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------
# KYC KMS Encryption
# ---------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "kyc" {
  bucket = aws_s3_bucket.kyc.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------
# KYC Public Access Block
# ---------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "kyc" {
  bucket = aws_s3_bucket.kyc.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------
# KYC Object Lock
# ---------------------------------------------------------

resource "aws_s3_bucket_object_lock_configuration" "kyc" {
  bucket = aws_s3_bucket.kyc.id

  depends_on = [
    aws_s3_bucket_versioning.kyc
  ]

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.kyc_retention_days
    }
  }
}

# ---------------------------------------------------------
# KYC Lifecycle
#
# CKV2_AWS_61
# CKV_AWS_300
#
# Current KYC objects are not automatically expired because
# Object Lock controls their required retention.
# ---------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "kyc" {
  bucket = aws_s3_bucket.kyc.id

  depends_on = [
    aws_s3_bucket_versioning.kyc,
    aws_s3_bucket_object_lock_configuration.kyc
  ]

  rule {
    id     = "kyc-noncurrent-version-retention"
    status = "Enabled"

    filter {}

    # Abort incomplete multipart uploads after 7 days.
    # Fixes CKV_AWS_300.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# ---------------------------------------------------------
# KYC Server Access Logging
# ---------------------------------------------------------

resource "aws_s3_bucket_logging" "kyc" {
  bucket = aws_s3_bucket.kyc.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "kyc/"
  depends_on    = [aws_s3_bucket_policy.access_logs]
}

# ---------------------------------------------------------
# KYC Event Notifications
#
# CKV2_AWS_62
# ---------------------------------------------------------

resource "aws_s3_bucket_notification" "kyc" {
  bucket      = aws_s3_bucket.kyc.id
  eventbridge = true
}

# =========================================================
# ELASTICACHE REDIS
# =========================================================

# ---------------------------------------------------------
# Redis Security Group
# ---------------------------------------------------------

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Allow Redis access only from application workloads"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-sg"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# Application -> Redis
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_to_redis" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = var.application_security_group_id

  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow Redis traffic from application security group"
}

# ---------------------------------------------------------
# Redis AUTH Password
# ---------------------------------------------------------

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

# ---------------------------------------------------------
# Redis AUTH Secret
# ---------------------------------------------------------

resource "aws_secretsmanager_secret" "redis" {
  name        = "${var.project_name}/${var.environment}/redis/auth"
  description = "Redis authentication token for ${var.project_name} ${var.environment}"
  kms_key_id  = var.kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-auth"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id

  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
  })
}

# ---------------------------------------------------------
# Redis Secret Rotation
#
# CKV2_AWS_57
# ---------------------------------------------------------

resource "aws_secretsmanager_secret_rotation" "redis" {
  count = var.redis_rotation_lambda_arn != null ? 1 : 0

  secret_id           = aws_secretsmanager_secret.redis.id
  rotation_lambda_arn = var.redis_rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [
    aws_secretsmanager_secret_version.redis
  ]
}

# ---------------------------------------------------------
# Redis Subnet Group
# ---------------------------------------------------------

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-redis-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-subnets"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# Redis Replication Group
# ---------------------------------------------------------

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project_name}-${var.environment}-redis"

  description = "${var.project_name} ${var.environment} Redis"

  engine    = "redis"
  node_type = var.redis_node_type

  num_cache_clusters = 2

  port = 6379

  subnet_group_name = aws_elasticache_subnet_group.this.name

  security_group_ids = [
    aws_security_group.redis.id
  ]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  kms_key_id = var.kms_key_arn

  auth_token = random_password.redis_auth.result

  auth_token_update_strategy = "SET"

  automatic_failover_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis"
    Environment = var.environment
  }
}
