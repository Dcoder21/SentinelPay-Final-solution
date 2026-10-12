# =========================================================
# LOCAL VALUES
# =========================================================

locals {
  name_prefix = var.name_prefix != null ? var.name_prefix : "${var.project_name}-${var.environment}"
}


# =========================================================
# ECS CLUSTER
# =========================================================

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-cluster"
      Environment = var.environment
    }
  )
}


# =========================================================
# ECS SECURITY GROUP
# =========================================================

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Security group for Sentinelpay ECS Fargate tasks"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-ecs-sg"
      Environment = var.environment
    }
  )
}


# =========================================================
# ALB -> ECS INGRESS
# =========================================================
# Only the ALB security group can reach the ECS application
# container port.
# =========================================================

resource "aws_vpc_security_group_ingress_rule" "alb_to_ecs" {
  for_each          = { payments = 8001, kyc = 8002 }
  security_group_id = aws_security_group.ecs.id

  referenced_security_group_id = var.alb_security_group_id

  from_port   = each.value
  to_port     = each.value
  ip_protocol = "tcp"

  description = "Allow application traffic from ALB to ECS tasks"
}


# =========================================================
# ECS EGRESS - HTTPS
# =========================================================
# With public HTTPS egress enabled, tasks reach registries and AWS APIs
# through NAT. Otherwise this rule only permits VPC-local endpoints such as:
#
# - ECR API
# - ECR Docker
# - Secrets Manager
# - KMS
# - CloudWatch Logs
#
# Internet access is limited to TCP 443 and must be enabled explicitly.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.allow_public_https_egress ? "0.0.0.0/0" : var.vpc_cidr

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "HTTPS image pulls and AWS APIs; internet access uses the private subnet NAT"
}


# =========================================================
# ECS EGRESS - POSTGRESQL
# =========================================================
# Allows ECS applications to connect to the private
# PostgreSQL RDS instance.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_to_postgres" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  description = "Allow ECS tasks to connect to PostgreSQL within the VPC"
}


# =========================================================
# ECS EGRESS - REDIS
# =========================================================
# Allows ECS applications to connect to private
# ElastiCache Redis.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_to_redis" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow ECS tasks to connect to Redis within the VPC"
}


# =========================================================
# ECS EGRESS - DNS UDP
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_dns_udp" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"

  description = "Allow ECS DNS queries over UDP within the VPC"
}


# =========================================================
# ECS EGRESS - DNS TCP
# =========================================================
# DNS can fall back to TCP for large responses.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_dns_tcp" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 53
  to_port     = 53
  ip_protocol = "tcp"

  description = "Allow ECS DNS queries over TCP within the VPC"
}


# =========================================================
# ECS TASK EXECUTION ROLE
# =========================================================

resource "aws_iam_role" "execution" {
  name        = "${local.name_prefix}-ecs-execution-role"
  description = "Execution role used by Sentinelpay ECS Fargate tasks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECSTaskExecutionAssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-ecs-execution-role"
      Environment = var.environment
    }
  )
}


# =========================================================
# ECS TASK EXECUTION POLICY
# =========================================================

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# =========================================================
# CLOUDWATCH LOG GROUP
# =========================================================

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/${local.name_prefix}"

  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-ecs-logs"
      Environment = var.environment
    }
  )
}



resource "aws_iam_role_policy" "execution_secrets" {
  name = "${local.name_prefix}-execution-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = var.secret_arns },
    { Effect = "Allow", Action = ["kms:Decrypt"], Resource = var.kms_key_arn }
  ] })
}
resource "aws_iam_role" "runtime" {
  for_each           = var.services
  name               = "${local.name_prefix}-${each.key}-runtime"
  assume_role_policy = aws_iam_role.execution.assume_role_policy
}
resource "aws_iam_role_policy" "kyc_documents" {
  name = "${local.name_prefix}-kyc-documents"
  role = aws_iam_role.runtime["kyc"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "arn:aws:s3:::${var.kyc_bucket}/users/*" },
    { Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = var.kms_key_arn }
  ] })
}
locals {
  tasks = merge(var.services, { migration = var.migration })
}
resource "aws_ecs_task_definition" "application" {
  for_each                 = local.tasks
  family                   = "${local.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = each.key == "migration" ? null : aws_iam_role.runtime[each.key].arn
  container_definitions = jsonencode([merge({
    name                   = each.key
    image                  = each.value.image
    essential              = true
    readonlyRootFilesystem = true
    environment            = [for k, v in each.value.environment : { name = k, value = v }]
    secrets                = [for k, v in each.value.secrets : { name = k, valueFrom = v }]
    portMappings           = each.key == "migration" ? [] : [{ containerPort = each.value.port, hostPort = each.value.port, protocol = "tcp" }]
    logConfiguration = { logDriver = "awslogs", options = {
      awslogs-group         = aws_cloudwatch_log_group.this.name
      awslogs-region        = var.aws_region
      awslogs-stream-prefix = each.key
    } }
  }, each.key == "migration" ? { command = ["python", "-m", "app.migrate"] } : {})])
  depends_on = [aws_iam_role_policy.execution_secrets, aws_iam_role_policy_attachment.execution]
}
resource "aws_ecs_service" "application" {
  for_each        = var.services
  name            = "${local.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.application[each.key].arn
  # Scanned images and schema are published before the workflow scales services.
  desired_count                     = 0
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 90
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = var.target_groups[each.key]
    container_name   = each.key
    container_port   = each.value.port
  }
  lifecycle { ignore_changes = [desired_count, task_definition] }
  depends_on = [aws_iam_role_policy.kyc_documents]
}
