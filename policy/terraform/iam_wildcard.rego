package terraform.iam

import rego.v1


# ---------------------------------------------------------
# SentinelPay Policy:
# Customer-managed IAM policies must not use wildcard actions
# ---------------------------------------------------------


deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_iam_policy"

    after := resource.change.after
    after != null

    statement := after.policy.Statement[_]
    action := statement.Action

    wildcard_action(action)

    msg := sprintf(
        "IAM policy '%s' contains wildcard action '%s'. Customer-managed policies must use least-privilege actions.",
        [resource.address, action],
    )
}


deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_iam_policy"

    after := resource.change.after
    after != null

    statement := after.policy.Statement[_]
    action := statement.Action[_]

    wildcard_action(action)

    msg := sprintf(
        "IAM policy '%s' contains wildcard action '%s'. Customer-managed policies must use least-privilege actions.",
        [resource.address, action],
    )
}


# ---------------------------------------------------------
# Helper:
# Detect full or service-level wildcard permissions
# ---------------------------------------------------------

wildcard_action(action) if {
    action == "*"
}

wildcard_action(action) if {
    endswith(action, ":*")
}
