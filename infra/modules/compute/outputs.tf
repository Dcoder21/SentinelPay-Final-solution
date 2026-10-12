output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.this.name
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}