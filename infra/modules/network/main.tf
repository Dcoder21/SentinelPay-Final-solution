# =========================================================
# VPC
# =========================================================

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc"
      Environment = var.environment
    }
  )
}

# =========================================================
# INTERNET GATEWAY
# =========================================================

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-igw"
      Environment = var.environment
    }
  )
}

# =========================================================
# PUBLIC SUBNETS
# =========================================================

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # CKV_AWS_130
  # Do not automatically assign public IP addresses.
  # ALB and NAT Gateway do not require this setting.
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-${count.index + 1}"
      Environment = var.environment
      Tier        = "public"
    }
  )
}

# =========================================================
# PRIVATE SUBNETS
# =========================================================

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-private-${count.index + 1}"
      Environment = var.environment
      Tier        = "private"
    }
  )
}

# =========================================================
# NAT GATEWAY
# =========================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [
    aws_internet_gateway.this
  ]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-nat-eip"
      Environment = var.environment
    }
  )
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [
    aws_internet_gateway.this
  ]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-nat"
      Environment = var.environment
    }
  )
}

# =========================================================
# PUBLIC ROUTE TABLE
# =========================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-rt"
      Environment = var.environment
    }
  )
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =========================================================
# PRIVATE ROUTE TABLE
# =========================================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-private-rt"
      Environment = var.environment
    }
  )
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =========================================================
# DEFAULT SECURITY GROUP
#
# Prevent use of the default VPC security group.
# No ingress or egress rules are permitted.
# =========================================================

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  ingress = []
  egress  = []

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-default-deny"
      Environment = var.environment
    }
  )
}

# =========================================================
# VPC FLOW LOG - CLOUDWATCH LOG GROUP
#
# CKV2_AWS_11
# CKV_AWS_158
# CKV_AWS_338
# =========================================================

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name = "/aws/vpc/${var.project_name}-${var.environment}/flow-logs"

  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc-flow-logs"
      Environment = var.environment
    }
  )
}

# =========================================================
# VPC FLOW LOG IAM ROLE
# =========================================================

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
      Environment = var.environment
    }
  )
}

# =========================================================
# VPC FLOW LOG IAM POLICY
# =========================================================

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.project_name}-${var.environment}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17" #tfsec:ignore:aws-iam-no-policy-wildcards

    Statement = [
      {
        Sid    = "WriteVPCFlowLogs"
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      },
      {
        Sid    = "DescribeVPCFlowLogStreams"
        Effect = "Allow"

        Action = [
          "logs:DescribeLogStreams"
        ]

        Resource = aws_cloudwatch_log_group.vpc_flow_logs.arn
      }
    ]
  })
}
# =========================================================
# VPC FLOW LOG
# =========================================================

resource "aws_flow_log" "this" {
  vpc_id = aws_vpc.this.id

  traffic_type = "ALL"

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn

  iam_role_arn = aws_iam_role.vpc_flow_logs.arn

  max_aggregation_interval = 60

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc-flow-log"
      Environment = var.environment
    }
  )

  depends_on = [
    aws_iam_role_policy.vpc_flow_logs
  ]
}