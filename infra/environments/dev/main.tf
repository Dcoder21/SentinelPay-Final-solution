module "network" { #tfsec:ignore:aws-iam-no-policy-wildcards
  source = "../../modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr = var.vpc_cidr

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones

  kms_key_arn = module.kms.key_arn

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


module "edge" {
  source = "../../modules/edge"

  project_name = var.project_name
  environment  = var.environment

  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr

  private_subnet_ids = module.network.private_subnet_ids

  container_port = var.container_port

  acm_certificate_arn    = var.acm_certificate_arn
  enable_http_smoke_test = var.enable_http_smoke_test

  alb_logs_bucket = module.data.alb_logs_bucket_name

  kms_key_arn = module.kms.key_arn
}


module "compute" {
  source = "../../modules/compute"

  project_name              = var.project_name
  environment               = var.environment
  name_prefix               = "${var.project_name}-${var.environment}"
  allow_public_https_egress = var.allow_public_https_egress

  # ======================================================
  # NETWORK
  # ======================================================

  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr

  private_subnet_ids = module.network.private_subnet_ids

  # ======================================================
  # ALB / EDGE
  # ======================================================

  alb_security_group_id = module.edge.alb_security_group_id
  target_group_arn      = module.edge.target_group_arn
  target_groups         = module.edge.target_groups
  services              = local.application_services
  migration             = local.migration_config
  secret_arns           = [aws_secretsmanager_secret.application.arn, module.data.redis_secret_arn, module.rds.master_secret_arn]
  kyc_bucket            = module.data.kyc_bucket_name
  listener_arn          = module.edge.listener_arn

  # ======================================================
  # ECS
  # ======================================================

  container_image = var.container_image
  container_port  = var.container_port
  desired_count   = var.desired_count

  # ======================================================
  # KMS / REGION
  # ======================================================

  kms_key_arn = module.kms.key_arn
  aws_region  = var.aws_region

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


module "security_iam" {
  source = "../../modules/security-iam"

  project_name = var.project_name
  environment  = var.environment
}


module "kms" {
  source = "../../modules/kms"

  project_name = var.project_name
  environment  = var.environment

  kms_admin_role_arns = [
    module.security_iam.kms_admin_role_arn
  ]

  kms_user_role_arns = [
    module.security_iam.kms_user_role_arn
  ]
}


module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  private_subnet_ids = module.network.private_subnet_ids

  application_security_group_id = (
    module.compute.ecs_security_group_id
  )

  kms_key_arn = module.kms.key_arn

  db_name     = "sentinelpay"
  db_username = "sentinelpay_admin"
}


data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


#trivy:ignore:AVD-AWS-0089
module "data" { #tfsec:ignore:aws-s3-enable-bucket-logging
  source = "../../modules/data"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  private_subnet_ids = module.network.private_subnet_ids

  application_security_group_id = module.compute.ecs_security_group_id

  kms_key_arn = module.kms.key_arn
}


module "detection" {
  source = "../../modules/detection"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id = module.network.vpc_id

  kms_key_arn = module.kms.key_arn

  cloudtrail_retention_days = 365
  private_subnet_ids        = module.network.private_subnet_ids
  enable_eks_guardduty      = false
}
