output "alb_dns_name" {
  value = aws_lb.this.dns_name
}
output "listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.private.arn
}
output "alb_security_group_id" {
  description = "Security group ID of the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.this["payments"].arn

}