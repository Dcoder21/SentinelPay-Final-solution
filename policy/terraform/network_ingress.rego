package terraform.network

import rego.v1


# ---------------------------------------------------------
# SentinelPay Policy:
# No 0.0.0.0/0 ingress except approved ALB HTTPS traffic
# ---------------------------------------------------------


deny contains msg if {
    resource := input.resource_changes[_]

    resource.type == "aws_security_group_rule"

    after := resource.change.after
    after != null

    after.type == "ingress"

    after.cidr_blocks[_] == "0.0.0.0/0"

    not approved_alb_https_rule(after)

    msg := sprintf(
        "Security group rule '%s' allows 0.0.0.0/0 ingress outside the approved ALB HTTPS exception.",
        [resource.address],
    )
}


approved_alb_https_rule(rule) if {
    rule.from_port == 443
    rule.to_port == 443
    rule.protocol == "tcp"
}
