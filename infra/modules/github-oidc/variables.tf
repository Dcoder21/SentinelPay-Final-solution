variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "github_organization" {
  description = "GitHub organization"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository"
  type        = string
}
variable "deployment_policy_json" {
  description = "IAM policy JSON for the GitHub Actions deployment role"
  type        = string
}
variable "github_branch" {
  type    = string
  default = "main"
}

variable "github_owner_id" { type = string }
variable "github_repository_id" { type = string }
