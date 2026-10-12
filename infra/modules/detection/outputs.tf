output "cloudtrail_name" {
  description = "CloudTrail trail name"
  value       = aws_cloudtrail.this.name
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail immutable S3 bucket"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.this.id
}

output "securityhub_enabled" {
  value = aws_securityhub_account.this.id
}

output "config_recorder_name" {
  value = aws_config_configuration_recorder.this.name
}

output "honeytoken_secret_arn" {
  description = "Secrets Manager ARN containing honeytoken credentials"
  value       = aws_secretsmanager_secret.honeytoken.arn
}

output "quarantine_security_group_id" {
  value = aws_security_group.quarantine.id
}

output "quarantine_lambda_name" {
  value = aws_lambda_function.quarantine.function_name
}