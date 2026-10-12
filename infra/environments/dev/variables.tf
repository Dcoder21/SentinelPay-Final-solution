# =========================================================
# AWS
# =========================================================

variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "eu-west-1"
}


# =========================================================
# PROJECT
# =========================================================

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "sentinelpay"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}


# =========================================================
# NETWORK
# =========================================================

variable "vpc_cidr" {
  description = "CIDR block of the VPC used to restrict ECS outbound traffic"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones for the VPC"
  type        = list(string)
}


# =========================================================
# ALB / TLS
# =========================================================

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate used by the ALB HTTPS listener"
  type        = string
  default     = null
}


# =========================================================
# ECS / COMPUTE
# =========================================================

variable "container_image" {
  description = "Docker image used by the ECS task"
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Port exposed by the ECS container"
  type        = number
  default     = 80
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "name_prefix" {
  description = "Prefix used for naming compute resources"
  type        = string
  default     = null
}


# =========================================================
# COMMON TAGS
# =========================================================

variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}
variable "enable_http_smoke_test" {
  description = "Temporary HTTP-only dev infrastructure test; never send payment data or credentials over HTTP"
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_http_smoke_test || var.environment == "dev"
    error_message = "HTTP smoke-test mode is permitted only for dev."
  }
}
variable "allow_public_https_egress" {
  description = "Allow ECS HTTPS through NAT for public registry image pulls and AWS APIs"
  type        = bool
  default     = false
}
