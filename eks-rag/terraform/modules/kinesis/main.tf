# Kinesis Data Stream for Real-Time Vehicle Error Logs

resource "aws_kinesis_stream" "error_logs" {
  name             = var.stream_name
  retention_period = 24

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = {
    Name        = var.stream_name
    Environment = "production"
    Purpose     = "real-time-rag-vehicle-logs"
  }
}
