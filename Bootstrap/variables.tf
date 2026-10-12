variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "sentinelpay"
}

variable "environment" {
  type    = string
  default = "dev"
}
variable "github_organization" {
  type    = string
  default = "Dcoder21"
}
variable "github_repository" {
  type    = string
  default = "SentinelPay-Final-solution"
}
variable "github_branch" {
  type    = string
  default = "main"
}
variable "github_owner_id" {
  type    = string
  default = "106084706"
}
variable "github_repository_id" {
  type    = string
  default = "1297165219"
}
