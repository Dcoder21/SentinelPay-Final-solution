output "permission_set_arn" {
  description = "IAM Identity Center permission set ARN"
  value       = aws_ssoadmin_permission_set.developer.arn
}

output "instance_arn" {
  description = "IAM Identity Center instance ARN"
  value       = local.identity_center_instance_arn
}