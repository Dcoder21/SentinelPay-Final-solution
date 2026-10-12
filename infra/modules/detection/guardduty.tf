resource "aws_guardduty_detector" "this" {
  # checkov:skip=CKV2_AWS_3:Development account is not configured as an AWS Organizations GuardDuty delegated administrator; GuardDuty is enabled directly in this account and region

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name        = "${var.project_name}-${var.environment}-guardduty"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# S3 Protection
# ---------------------------------------------------------

resource "aws_guardduty_detector_feature" "s3" {
  detector_id = aws_guardduty_detector.this.id

  name   = "S3_DATA_EVENTS"
  status = "ENABLED"
}

# ---------------------------------------------------------
# EBS Malware Protection
# ---------------------------------------------------------

resource "aws_guardduty_detector_feature" "ebs_malware" {
  detector_id = aws_guardduty_detector.this.id

  name   = "EBS_MALWARE_PROTECTION"
  status = "ENABLED"
}

# ---------------------------------------------------------
# RDS Protection
# ---------------------------------------------------------

resource "aws_guardduty_detector_feature" "rds" {
  detector_id = aws_guardduty_detector.this.id

  name   = "RDS_LOGIN_EVENTS"
  status = "ENABLED"
}

# ---------------------------------------------------------
# Lambda Protection
# ---------------------------------------------------------

resource "aws_guardduty_detector_feature" "lambda" {
  detector_id = aws_guardduty_detector.this.id

  name   = "LAMBDA_NETWORK_LOGS"
  status = "ENABLED"
}

# ---------------------------------------------------------
# EKS Audit Log Protection
# ---------------------------------------------------------

resource "aws_guardduty_detector_feature" "eks" {
  count = var.enable_eks_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this.id

  name   = "EKS_AUDIT_LOGS"
  status = "ENABLED"
}