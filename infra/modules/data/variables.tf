variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "application_security_group_id" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "kyc_retention_days" {
  type    = number
  default = 90
}

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}
variable "redis_rotation_lambda_arn" {
  description = "ARN of the Lambda function used to rotate the Redis authentication secret"
  type        = string
  default     = null
}