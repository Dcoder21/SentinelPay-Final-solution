variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the ALB security group is created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC used to restrict ALB egress"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by the ALB and VPC link"
  type        = list(string)
}

variable "container_port" {
  description = "Application container port"
  type        = number
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = null
}

variable "alb_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt WAF CloudWatch logs"
  type        = string
}

variable "enable_http_smoke_test" {
  type    = bool
  default = false
}
