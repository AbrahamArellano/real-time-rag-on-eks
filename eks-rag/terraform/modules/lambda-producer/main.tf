# Lambda Producer - Generates IoT Vehicle Error Logs and Publishes to Kinesis

# Package Lambda code
data "archive_file" "producer_code" {
  type        = "zip"
  source_file = "${path.module}/lambda_code/producer.py"
  output_path = "${path.module}/lambda_code/producer.zip"
}

# Lambda Function
resource "aws_lambda_function" "producer" {
  filename         = data.archive_file.producer_code.output_path
  function_name    = "vehicle-log-producer"
  role             = aws_iam_role.producer.arn
  handler          = "producer.lambda_handler"
  source_code_hash = data.archive_file.producer_code.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      KINESIS_STREAM_NAME = var.kinesis_stream_name
      LOGS_PER_INVOCATION = var.logs_per_invocation
    }
  }

  tags = {
    Name    = "vehicle-log-producer"
    Purpose = "generate-iot-vehicle-logs"
  }
}

# EventBridge Rule for scheduled execution
resource "aws_cloudwatch_event_rule" "producer_schedule" {
  name                = "vehicle-log-producer-schedule"
  description         = "Trigger vehicle log producer Lambda"
  schedule_expression = var.schedule_expression

  tags = {
    Name = "vehicle-log-producer-schedule"
  }
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "producer" {
  rule      = aws_cloudwatch_event_rule.producer_schedule.name
  target_id = "vehicle-log-producer"
  arn       = aws_lambda_function.producer.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.producer_schedule.arn
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "producer" {
  name              = "/aws/lambda/${aws_lambda_function.producer.function_name}"
  retention_in_days = 7

  tags = {
    Name = "vehicle-log-producer-logs"
  }
}
