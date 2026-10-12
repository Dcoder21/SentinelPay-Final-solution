# API Gateway is the only public HTTPS endpoint. Backend traffic stays private.
resource "aws_security_group" "gateway" {
  name        = "${var.project_name}-${var.environment}-gateway"
  description = "API Gateway VPC link"
  vpc_id      = var.vpc_id
}
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Private ALB accepts only the API Gateway VPC link"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "gateway_to_alb" {
  # checkov:skip=CKV_AWS_260:Source is exclusively VPC link security group, not a public CIDR
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.gateway.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "Private API Gateway integration"
}
resource "aws_vpc_security_group_egress_rule" "gateway_to_alb" {
  security_group_id            = aws_security_group.gateway.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "Private ALB listener"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  for_each          = { payments = 8001, kyc = 8002 }
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
  description       = "Private application target"
}
resource "aws_lb" "this" {
  # checkov:skip=CKV2_AWS_20:Public TLS terminates at API Gateway; internal ALB accepts only VPC link SG on port 80
  # checkov:skip=CKV2_AWS_76:WAF association below includes AWS managed known bad inputs
  name                       = "${var.project_name}-${var.environment}-alb"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.private_subnet_ids
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  enable_http2               = true
  access_logs {
    bucket  = var.alb_logs_bucket
    prefix  = "alb"
    enabled = true
  }
}
resource "aws_lb_target_group" "this" {
  for_each = { payments = 8001, kyc = 8002 }
  # checkov:skip=CKV_AWS_378:API Gateway terminates public TLS; backend targets remain private
  name        = "${var.project_name}-${var.environment}-${each.key}"
  port        = each.value
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = each.key == "kyc" ? "/kyc/health" : "/health"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}
# tfsec:ignore:aws-elb-http-not-used Public HTTPS terminates at API Gateway; this listener is private and SG restricted.
resource "aws_lb_listener" "private" {
  # checkov:skip=CKV_AWS_2:Private VPC link backend only; AWS managed HTTPS endpoint terminates public TLS
  # checkov:skip=CKV_AWS_103:Private VPC link backend only; AWS managed HTTPS endpoint terminates public TLS
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["payments"].arn
  }
}
resource "aws_lb_listener_rule" "kyc" {
  listener_arn = aws_lb_listener.private.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["kyc"].arn
  }
  condition {
    path_pattern { values = ["/v1/verify*", "/v1/documents*", "/kyc/*"] }
  }
}
# ---------------------------------------------------------
# AWS WAFv2 Web ACL
# ---------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  name  = "${var.project_name}-${var.environment}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # -------------------------------------------------------
  # AWS Managed Common Rule Set
  # -------------------------------------------------------

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------
  # AWS Known Bad Inputs / Log4j Protection
  # ---------------------------------------------------------

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf"
  }
}

# ---------------------------------------------------------
# Associate WAF with ALB
# ---------------------------------------------------------

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# ---------------------------------------------------------
# WAF CloudWatch Log Group
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf" {
  name = "aws-waf-logs-${var.project_name}-${var.environment}"

  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "aws-waf-logs-${var.project_name}-${var.environment}"
  }
}

# ---------------------------------------------------------
# WAF Logging Configuration
# ---------------------------------------------------------

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn = aws_wafv2_web_acl.this.arn

  log_destination_configs = [
    aws_cloudwatch_log_group.waf.arn
  ]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.waf,
    aws_wafv2_web_acl.this
  ]
}
