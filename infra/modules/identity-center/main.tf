data "aws_ssoadmin_instances" "this" {}

locals {
  identity_center_instance_arn = tolist(
    data.aws_ssoadmin_instances.this.arns
  )[0]
}

resource "aws_ssoadmin_permission_set" "developer" {
  name = "${var.project_name}-Developer"

  description = "Developer access"

  instance_arn = local.identity_center_instance_arn

  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "developer" {
  instance_arn = local.identity_center_instance_arn

  permission_set_arn = aws_ssoadmin_permission_set.developer.arn

  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}