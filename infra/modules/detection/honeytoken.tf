# =========================================================
# IAM HONEYTOKEN USER
#
# This IAM user is intentionally created as a deception
# credential. It MUST NOT receive any IAM permissions.
#
# Any attempted use of its access key should be treated as
# a security incident.
# =========================================================

resource "aws_iam_user" "honeytoken" {
  # checkov:skip=CKV_AWS_273:This IAM user is intentionally created as a security honeytoken and must not use IAM Identity Center

  name = "${var.project_name}-${var.environment}-honeytoken"

  tags = {
    Name        = "${var.project_name}-${var.environment}-honeytoken"
    Purpose     = "Security honeytoken"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# =========================================================
# HONEYTOKEN ACCESS KEY
#
# Intentionally creates an access key that should NEVER
# legitimately be used.
#
# No IAM policies should be attached to the honeytoken user.
# =========================================================

resource "aws_iam_access_key" "honeytoken" {
  user = aws_iam_user.honeytoken.name
}

# =========================================================
# SECRETS MANAGER SECRET
#
# Stores the honeytoken credentials securely using the
# project's customer-managed KMS key.
# =========================================================

resource "aws_secretsmanager_secret" "honeytoken" {
  # checkov:skip=CKV2_AWS_57:Automatic rotation is intentionally disabled because this is a security honeytoken; rotating the credential would require synchronised updates to the detection rule

  name        = "${var.project_name}/${var.environment}/honeytoken"
  description = "Security honeytoken credentials - do not use"

  kms_key_id = var.kms_key_arn

  recovery_window_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-honeytoken-secret"
    Purpose     = "Security honeytoken"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
# =========================================================
# HONEYTOKEN SECRET VERSION
# =========================================================

resource "aws_secretsmanager_secret_version" "honeytoken" {
  secret_id = aws_secretsmanager_secret.honeytoken.id

  secret_string = jsonencode({
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.honeytoken.id # gitleaks:allow Terraform reference, no embedded credential
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.honeytoken.secret # gitleaks:allow Terraform reference, no embedded credential
  })
}

# =========================================================
# EVENTBRIDGE RULE
#
# Detects any AWS API call made using the honeytoken
# access key.
#
# CloudTrail must be enabled for this detection to work.
# =========================================================

resource "aws_cloudwatch_event_rule" "honeytoken" {
  name = "${var.project_name}-${var.environment}-honeytoken-used"

  description = "Detects attempted use of SentinelPay honeytoken credentials"

  event_pattern = jsonencode({
    "detail-type" = [
      "AWS API Call via CloudTrail"
    ]

    detail = {
      userIdentity = {
        accessKeyId = [
          aws_iam_access_key.honeytoken.id
        ]
      }
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-honeytoken-used"
    Purpose     = "Honeytoken detection"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}