output "kyc_bucket_name" {
  value = aws_s3_bucket.kyc.bucket
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_secret_arn" {
  value = aws_secretsmanager_secret.redis.arn
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}
output "access_logs_bucket_name" {
  description = "Name of the S3 server access log destination"
  value       = aws_s3_bucket.access_logs.bucket
}

output "alb_logs_bucket_name" {
  value = aws_s3_bucket.alb_logs.bucket
  depends_on = [
    aws_s3_bucket_policy.alb_logs,
    aws_s3_bucket_server_side_encryption_configuration.alb_logs,
    aws_s3_bucket_public_access_block.alb_logs
  ]
}
