output "kms_admin_role_arn" {
  description = "ARN of the KMS administrator role"
  value       = aws_iam_role.kms_admin.arn
}

output "kms_user_role_arn" {
  description = "ARN of the KMS key user role"
  value       = aws_iam_role.kms_user.arn
}