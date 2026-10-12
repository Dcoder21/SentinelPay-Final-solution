# Secrets are generated once and retained in the encrypted remote state.
resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 3072
}
resource "random_password" "application" {
  for_each = toset(["database", "rate_limit", "session"])
  length   = 48
  special  = false
}
resource "aws_secretsmanager_secret" "application" {
  name       = "${var.project_name}/${var.environment}/application"
  kms_key_id = module.kms.key_arn
}
resource "aws_secretsmanager_secret_version" "application" {
  secret_id = aws_secretsmanager_secret.application.id
  secret_string = jsonencode({
    JWT_PRIVATE_KEY       = tls_private_key.jwt.private_key_pem
    JWT_PUBLIC_KEY        = tls_private_key.jwt.public_key_pem
    DB_PASSWORD           = random_password.application["database"].result
    RATE_LIMIT_KEY_SECRET = random_password.application["rate_limit"].result
    SESSION_SIGNING_KEY   = random_password.application["session"].result
  })
}
locals {
  db_environment = {
    DB_HOST                 = module.rds.endpoint
    DB_PORT                 = "5432"
    DB_NAME                 = "sentinelpay"
    DB_USERNAME             = "sentinelpay_app"
    DB_SSLROOTCERT          = "/app/rds-global-bundle.pem"
    ENVIRONMENT             = "testing"
    AWS_REGION              = var.aws_region
    PYTHONDONTWRITEBYTECODE = "1"
  }
  public_secrets = {
    DB_PASSWORD    = "${aws_secretsmanager_secret_version.application.secret_id}:DB_PASSWORD::"
    JWT_PUBLIC_KEY = "${aws_secretsmanager_secret_version.application.secret_id}:JWT_PUBLIC_KEY::"
  }
  application_services = {
    payments = {
      image       = "${aws_ecr_repository.application["payments-api"].repository_url}:${var.image_tag}"
      port        = 8001
      environment = merge(local.db_environment, { REDIS_HOST = module.data.redis_endpoint })
      secrets = merge(local.public_secrets, {
        JWT_PRIVATE_KEY       = "${aws_secretsmanager_secret_version.application.secret_id}:JWT_PRIVATE_KEY::"
        RATE_LIMIT_KEY_SECRET = "${aws_secretsmanager_secret_version.application.secret_id}:RATE_LIMIT_KEY_SECRET::"
        SESSION_SIGNING_KEY   = "${aws_secretsmanager_secret_version.application.secret_id}:SESSION_SIGNING_KEY::"
        REDIS_AUTH_TOKEN      = "${module.data.redis_secret_arn}:auth_token::"
      })
    }
    kyc = {
      image       = "${aws_ecr_repository.application["kyc-api"].repository_url}:${var.image_tag}"
      port        = 8002
      environment = merge(local.db_environment, { KYC_BUCKET = module.data.kyc_bucket_name })
      secrets     = local.public_secrets
    }
  }
  migration_config = {
    image       = local.application_services.payments.image
    port        = 8001
    environment = merge(local.db_environment, { DB_USERNAME = "sentinelpay_admin" })
    secrets = {
      DB_PASSWORD     = "${module.rds.master_secret_arn}:password::"
      APP_DB_PASSWORD = "${aws_secretsmanager_secret_version.application.secret_id}:DB_PASSWORD::"
    }
  }
}
