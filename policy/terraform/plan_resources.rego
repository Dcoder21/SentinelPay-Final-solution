package terraform.plan_resources

import rego.v1

# The AWS provider uses this resource type for the actual ALB/ECS rules.
deny contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_vpc_security_group_ingress_rule"
    after := resource.change.after
    after != null
    public_ingress(after)
    not approved_edge_rule(resource, after)
    msg := sprintf("Public ingress is not approved for '%s'.", [resource.address])
}

public_ingress(rule) if { rule.cidr_ipv4 == "0.0.0.0/0" }
public_ingress(rule) if { rule.cidr_ipv6 == "::/0" }

approved_edge_rule(resource, rule) if {
    resource.address == "module.edge.aws_vpc_security_group_ingress_rule.https"
    rule.from_port == 443
    rule.to_port == 443
    rule.ip_protocol == "tcp"
}

approved_edge_rule(resource, rule) if {
    resource.address == "module.edge.aws_vpc_security_group_ingress_rule.http_redirect"
    rule.from_port == 80
    rule.to_port == 80
    rule.ip_protocol == "tcp"
    input.variables.acm_certificate_arn.value != null
}

approved_edge_rule(resource, rule) if {
    resource.address == "module.edge.aws_vpc_security_group_ingress_rule.http_redirect"
    rule.from_port == 80
    rule.to_port == 80
    rule.ip_protocol == "tcp"
    input.variables.environment.value == "dev"
    input.variables.enable_http_smoke_test.value == true
}

# Real plan policies are JSON strings, unlike the original object fixtures.
deny contains msg if {
    resource := input.resource_changes[_]
    resource.type in {"aws_iam_policy", "aws_iam_role_policy", "aws_iam_user_policy"}
    after := resource.change.after
    after != null
    is_string(after.policy)
    policy := json.unmarshal(after.policy)
    statement := policy.Statement[_]
    statement.Effect == "Allow"
    action := policy_actions(statement.Action)[_]
    action == "*"
    msg := sprintf("IAM policy '%s' allows all actions.", [resource.address])
}

deny contains msg if {
    resource := input.resource_changes[_]
    resource.type in {"aws_iam_policy", "aws_iam_role_policy", "aws_iam_user_policy"}
    after := resource.change.after
    after != null
    is_string(after.policy)
    policy := json.unmarshal(after.policy)
    statement := policy.Statement[_]
    statement.Effect == "Allow"
    action := policy_actions(statement.Action)[_]
    endswith(action, ":*")
    msg := sprintf("IAM policy '%s' allows service-wide action '%s'.", [resource.address, action])
}

policy_actions(action) := [action] if { is_string(action) }
policy_actions(action) := action if { is_array(action) }
