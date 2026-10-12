# One-time identity prerequisite. This role cannot edit its own trust or the
# GitHub provider; application infrastructure is managed by the gated workflow.
resource "aws_iam_role" "github_infrastructure" {
  name                 = "${var.project_name}-${var.environment}-github-infrastructure"
  max_session_duration = 7200
  assume_role_policy   = data.aws_iam_policy_document.infrastructure_trust.json
}

data "aws_iam_policy_document" "infrastructure_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.github_oidc.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_organization}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:ref:refs/heads/${var.github_branch}",
        "repo:${var.github_organization}/${var.github_repository}:ref:refs/heads/${var.github_branch}"
      ]
    }
  }
}

resource "aws_iam_role_policy" "github_infrastructure" {
  name = "${var.project_name}-${var.environment}-terraform"
  role = aws_iam_role.github_infrastructure.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProvisionStackServices"
        Effect = "Allow"
        Action = [
          "ec2:*", "ecs:*", "elasticloadbalancing:*", "wafv2:*",
          "rds:*", "elasticache:*", "kms:*", "secretsmanager:*",
          "logs:*", "cloudtrail:*", "config:*", "guardduty:*",
          "securityhub:*", "events:*", "lambda:*", "signer:*",
          "sns:*", "sqs:*", "ecr:*"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid    = "ProjectBuckets"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-*",
          "arn:aws:s3:::${var.project_name}-${var.environment}-*/*"
        ]
      },
      {
        Sid      = "AccountS3PublicAccessBlock"
        Effect   = "Allow"
        Action   = ["s3:GetAccountPublicAccessBlock", "s3:PutAccountPublicAccessBlock", "s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Sid      = "ReadStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Sid      = "DevStateObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.terraform_state.arn}/environments/dev/terraform.tfstate"
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
      {
        Sid    = "ProjectWorkloadRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:GetRole", "iam:DeleteRole", "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-*"
      },
      {
        Sid      = "PassWorkloadRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-*"
        Condition = { StringEquals = { "iam:PassedToService" = [
          "ecs-tasks.amazonaws.com", "lambda.amazonaws.com", "monitoring.rds.amazonaws.com",
          "cloudtrail.amazonaws.com", "config.amazonaws.com"
        ] } }
      },
      {
        Sid      = "ReadAWSManagedPolicies"
        Effect   = "Allow"
        Action   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
        Resource = "arn:aws:iam::aws:policy/*"
      },
      {
        Sid      = "AWSServiceLinkedRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole", "iam:GetRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
      },
      {
        Sid    = "ProtectBootstrapIdentity"
        Effect = "Deny"
        Action = "iam:*"
        Resource = [aws_iam_role.github_infrastructure.arn, module.github_oidc.role_arn,
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
      }
    ]
  })
}

output "github_infrastructure_role_arn" {
  value = aws_iam_role.github_infrastructure.arn
}

output "github_application_role_arn" {
  value = module.github_oidc.role_arn
}
