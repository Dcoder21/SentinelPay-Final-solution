output "secret_arn" {
  value = aws_secretsmanager_secret.database.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.database.name
}

output "rotation_lambda_arn" {
  value = aws_lambda_function.rotation.arn
}

output "rotation_security_group_id" {
  value = aws_security_group.rotation.id
}