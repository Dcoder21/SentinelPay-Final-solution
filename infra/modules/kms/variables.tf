variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "kms_admin_role_arns" {
  type = list(string)
}

variable "kms_user_role_arns" {
  type = list(string)
}