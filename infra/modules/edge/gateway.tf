resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
}
resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.project_name}-${var.environment}-link"
  security_group_ids = [aws_security_group.gateway.id]
  subnet_ids         = var.private_subnet_ids
}
resource "aws_apigatewayv2_integration" "this" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.private.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"
  request_parameters     = { "overwrite:path" = "$request.path" }
}
resource "aws_apigatewayv2_route" "this" {
  # checkov:skip=CKV_AWS_309:Registration/login/health are public; Flask RS256 authorization protects private application routes
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
}
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.gateway.arn
    format          = jsonencode({ requestId = "$context.requestId", status = "$context.status", path = "$context.path", integrationError = "$context.integrationErrorMessage" })
  }
}
output "api_url" { value = aws_apigatewayv2_api.this.api_endpoint }
output "target_groups" {
  depends_on = [aws_lb_listener.private, aws_lb_listener_rule.kyc]
  value      = { for k, v in aws_lb_target_group.this : k => v.arn }
}
