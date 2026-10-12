# Application repositories are prepared for the later image deployment workflow.
resource "aws_ecr_repository" "application" {
  for_each             = toset(["payments-api", "kyc-api"])
  name                 = "${var.project_name}-${var.environment}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = module.kms.key_arn
  }
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.application : name => repository.repository_url }
}
