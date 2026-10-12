data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  github_deployment_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      {
        Sid    = "ECRImageManagement"
        Effect = "Allow"

        Action = [
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]

        Resource = [
          "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-${var.environment}-payments-api",
          "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-${var.environment}-kyc-api"
        ]
      },

      {
        Sid    = "ECSDeploy"
        Effect = "Allow"

        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]

        Resource = [
          "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${var.project_name}-${var.environment}-cluster/${var.project_name}-${var.environment}-service"
        ]
      },

      {
        Sid    = "ECSTaskDefinitionManagement"
        Effect = "Allow"

        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition"
        ]

        Resource = "*"
      },

      {
        Sid    = "PassECSTaskRoles"
        Effect = "Allow"

        Action = [
          "iam:PassRole"
        ]

        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-ecs-execution-role"
        ]

        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}


module "github_oidc" {
  source = "../infra/modules/github-oidc"

  project_name           = var.project_name
  environment            = var.environment
  github_organization    = var.github_organization
  github_repository      = var.github_repository
  github_branch          = var.github_branch
  github_owner_id        = var.github_owner_id
  github_repository_id   = var.github_repository_id
  deployment_policy_json = local.github_deployment_policy
}


