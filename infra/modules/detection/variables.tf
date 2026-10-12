variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "cloudtrail_retention_days" {
  type    = number
  default = 365
}

variable "enable_eks_guardduty" {
  type    = bool
  default = false
}

variable "private_subnet_ids" {
  type = list(string)
}
