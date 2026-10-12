data "aws_caller_identity" "current" {}

# ----------------------------------------
# KMS Administrator Role
# ----------------------------------------

resource "aws_iam_role" "kms_admin" {
  name = "${var.project_name}-${var.environment}-kms-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-kms-admin"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ----------------------------------------
# KMS User Role
# ----------------------------------------

resource "aws_iam_role" "kms_user" {
  name = "${var.project_name}-${var.environment}-kms-user"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-kms-user"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}