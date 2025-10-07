# Lambda Consumer - Consumes from Kinesis, generates embeddings, indexes to OpenSearch

# Package Lambda code
data "archive_file" "consumer_code" {
  type        = "zip"
  source_file = "${path.module}/lambda_code/consumer.py"
  output_path = "${path.module}/lambda_code/consumer.zip"
}

# Lambda Function
resource "aws_lambda_function" "consumer" {
  filename         = data.archive_file.consumer_code.output_path
  function_name    = "vehicle-log-consumer"
  role             = aws_iam_role.consumer.arn
  handler          = "consumer.lambda_handler"
  source_code_hash = data.archive_file.consumer_code.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 512

  layers = [
    var.aws4auth_layer_arn,
    var.opensearch_layer_arn
  ]

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = var.opensearch_endpoint
      INDEX_NAME          = var.index_name
    }
  }

  reserved_concurrent_executions = 10

  tags = {
    Name    = "vehicle-log-consumer"
    Purpose = "kinesis-to-opensearch-indexing"
  }
}

# Kinesis Event Source Mapping
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = var.kinesis_stream_arn
  function_name     = aws_lambda_function.consumer.arn
  starting_position = "LATEST"

  # Batch configuration
  batch_size                         = 100
  maximum_batching_window_in_seconds = 10

  depends_on = [
    aws_iam_role_policy.kinesis_read,
    aws_lambda_function.consumer
  ]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${aws_lambda_function.consumer.function_name}"
  retention_in_days = 7

  tags = {
    Name = "vehicle-log-consumer-logs"
  }
}
