variable "project_name" {
  type = string
}

variable "permission_set_name" {
  type    = string
  default = "Developer"
}

variable "session_duration" {
  description = "Maximum Identity Center session duration"
  type        = string
  default     = "PT4H"
}

variable "managed_policy_arn" {
  type    = string
  default = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}