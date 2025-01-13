terraform {
  required_version = "~> 1.10.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  cloud {
    workspaces {
      name = "run-task-resources"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# HMACシークレットキーの生成
resource "random_password" "hmac_key" {
  length  = 32
  special = true
}

# Lambda用のIAMロール
resource "aws_iam_role" "lambda_role" {
  name = "terraform-run-task-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda用のCloudWatch Logsポリシー
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Parameter Store にシークレットキーを保存
resource "aws_ssm_parameter" "hmac_secret" {
  name        = "/terraform-run-task/hmac-secret-key"
  description = "HMAC secret key for Terraform Run Task"
  type        = "SecureString"
  value       = random_password.hmac_key.result

  tags = {
    Environment = var.environment
  }
}

# Lambda用のIAMロールにParameter Store読み取り権限を追加
resource "aws_iam_role_policy" "lambda_ssm" {
  name = "terraform-run-task-ssm-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          aws_ssm_parameter.hmac_secret.arn,
        ]
      }
    ]
  })
}

# Lambda関数のソースコードをZIP化
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

locals {
  # リージョンごとのレイヤー情報マッピング
  extension_layers = {
    "ap-northeast-1" = {
      account_id = "133490724326"
      version    = "12"
    }
    "ap-northeast-3" = {
      account_id = "576959938190"
      version    = "12"
    }
    "us-east-1" = {
      account_id = "177933569100"
      version    = "12"
    }
    "us-east-2" = {
      account_id = "590474943231"
      version    = "14"
    }
    # 必要に応じて追加
  }

  extension_layer_arn = "arn:aws:lambda:${var.aws_region}:${local.extension_layers[var.aws_region].account_id}:layer:AWS-Parameters-and-Secrets-Lambda-Extension:${local.extension_layers[var.aws_region].version}"
}

# Lambda関数
resource "aws_lambda_function" "run_task" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "terraform-run-task-validator"
  role             = aws_iam_role.lambda_role.arn
  handler          = "main.handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128

  layers = [local.extension_layer_arn]

  environment {
    variables = {
      HMAC_SECRET_KEY_PARAM                  = aws_ssm_parameter.hmac_secret.name
      PARAMETERS_SECRETS_EXTENSION_HTTP_PORT = "2773"
      PARAMETERS_SECRETS_EXTENSION_LOG_LEVEL = "DEBUG"
    }
  }
}

# Lambda Function URL
resource "aws_lambda_function_url" "run_task" {
  function_name      = aws_lambda_function.run_task.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    max_age       = 86400
  }
}
