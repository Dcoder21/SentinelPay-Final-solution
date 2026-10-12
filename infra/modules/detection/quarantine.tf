resource "aws_security_group" "quarantine" {
  name        = "${var.project_name}-${var.environment}-quarantine"
  description = "Isolation security group for compromised resources"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-quarantine"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.project_name}-${var.environment}-guardduty-high"
  description = "Triggers automated containment for high-severity GuardDuty findings"

  event_pattern = jsonencode({
    source = [
      "aws.guardduty"
    ]

    "detail-type" = [
      "GuardDuty Finding"
    ]

    detail = {
      severity = [
        {
          numeric = [
            ">=",
            7
          ]
        }
      ]
    }
  })
}

resource "aws_iam_role" "quarantine" {
  name = "${var.project_name}-${var.environment}-quarantine-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "quarantine" {
  role = aws_iam_role.quarantine.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "DescribeNetworkInterfaces"
        Effect = "Allow"

        Action = [
          "ec2:DescribeNetworkInterfaces"
        ]

        Resource = "*"
      },

      {
        Sid    = "ManageLambdaNetworkInterfaces"
        Effect = "Allow"

        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute"
        ]

        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
      },

      {
        Sid    = "CreateLambdaLogGroup"
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup"
        ]

        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.environment}-quarantine"
      },

      {
        Sid    = "WriteLambdaLogs"
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.environment}-quarantine:*"
      },

      {
        Sid    = "WriteXRayTracing"
        Effect = "Allow"

        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]

        Resource = "*"
      },

      {
        Sid    = "SendToDeadLetterQueue"
        Effect = "Allow"

        Action = [
          "sqs:SendMessage"
        ]

        Resource = aws_sqs_queue.quarantine_dlq.arn
      },
      {
        Sid      = "EncryptDeadLetterMessages"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# The responder needs API connectivity; the isolation SG must have no egress.
resource "aws_security_group" "responder" {
  name        = "${var.project_name}-${var.environment}-responder"
  description = "HTTPS API access for the containment Lambda"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "responder_https" {
  security_group_id = aws_security_group.responder.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_iam_role_policy_attachment" "quarantine_vpc_access" {
  role       = aws_iam_role.quarantine.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "archive_file" "quarantine" {
  type = "zip"

  source_file = "${path.module}/lambda/quarantine.py"
  output_path = "${path.module}/quarantine.zip"
}

# Lambda code-signing profile
resource "aws_signer_signing_profile" "quarantine" {
  platform_id = "AWSLambda-SHA384-ECDSA"

  name_prefix = "${var.project_name}_${var.environment}_quarantine_"
}

# Lambda code-signing configuration
resource "aws_lambda_code_signing_config" "quarantine" {
  description = "Code signing configuration for quarantine Lambda"

  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.quarantine.version_arn
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "quarantine_dlq" {
  name              = "${var.project_name}-${var.environment}-quarantine-dlq"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_lambda_function" "quarantine" {
  function_name = "${var.project_name}-${var.environment}-quarantine"

  role    = aws_iam_role.quarantine.arn
  runtime = "python3.13"
  handler = "quarantine.lambda_handler"

  filename         = data.archive_file.quarantine.output_path
  source_code_hash = data.archive_file.quarantine.output_base64sha256

  # CKV_AWS_173
  kms_key_arn = var.kms_key_arn

  # CKV_AWS_272
  code_signing_config_arn = aws_lambda_code_signing_config.quarantine.arn

  # CKV_AWS_115
  reserved_concurrent_executions = 5

  # CKV_AWS_50
  tracing_config {
    mode = "Active"
  }

  # CKV_AWS_116
  dead_letter_config {
    target_arn = aws_sqs_queue.quarantine_dlq.arn
  }

  # CKV_AWS_117
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.responder.id]
  }

  environment {
    variables = {
      QUARANTINE_SG = aws_security_group.quarantine.id
    }
  }

  depends_on = [
    aws_iam_role_policy.quarantine,
    aws_iam_role_policy_attachment.quarantine_vpc_access,
    aws_vpc_security_group_egress_rule.responder_https
  ]
}

resource "aws_cloudwatch_event_target" "guardduty" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "QuarantineLambda"

  arn = aws_lambda_function.quarantine.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id = "AllowEventBridgeGuardDuty"

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quarantine.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high.arn
}
