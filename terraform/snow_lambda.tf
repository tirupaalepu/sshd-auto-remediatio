# ServiceNow incident Lambda (SNS → Table API)
# Secrets come from AWS Secrets Manager (created outside TF or via snow_secret.tf).

variable "snow_secret_name" {
  type        = string
  default     = "sshd-auto-remediation/servicenow"
  description = "Secrets Manager secret with keys: instance, user, password"
}

data "archive_file" "snow_incident_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/snow_incident/handler.py"
  output_path = "${path.module}/build/snow_incident.zip"
}

data "aws_secretsmanager_secret" "snow" {
  name = var.snow_secret_name
}

resource "aws_iam_role" "lambda_snow" {
  name = "${var.project_name}-lambda-snow"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_snow.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_snow_secret" {
  name = "${var.project_name}-lambda-snow-secret"
  role = aws_iam_role.lambda_snow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [data.aws_secretsmanager_secret.snow.arn]
    }]
  })
}

resource "aws_lambda_function" "snow_incident" {
  function_name = "${var.project_name}-snow-incident"
  role          = aws_iam_role.lambda_snow.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  filename      = data.archive_file.snow_incident_zip.output_path
  source_code_hash = data.archive_file.snow_incident_zip.output_base64sha256

  environment {
    variables = {
      SNOW_SECRET_ARN = data.aws_secretsmanager_secret.snow.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_snow_secret,
  ]
}

resource "aws_sns_topic_subscription" "snow_lambda" {
  topic_arn = aws_sns_topic.sshd_alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.snow_incident.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snow_incident.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.sshd_alarms.arn
}

output "snow_lambda_name" {
  value = aws_lambda_function.snow_incident.function_name
}

output "snow_secret_name" {
  value = var.snow_secret_name
}
