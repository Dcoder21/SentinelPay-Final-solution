output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.application["payments"].name
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}
output "application_deployment" {
  value      = { for k, v in aws_ecs_service.application : k => { service = v.name, task_definition = aws_ecs_task_definition.application[k].arn } }
  depends_on = [var.listener_arn]
}
output "migration_task" { value = aws_ecs_task_definition.application["migration"].arn }
