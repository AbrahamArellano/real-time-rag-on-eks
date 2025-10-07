# Lambda Layers for Lambda Consumer

# Upload existing layers from pythonLambdaLayers directory
resource "aws_lambda_layer_version" "aws4auth" {
  filename            = "${var.layers_source_dir}/aws4auth-layer.zip"
  layer_name          = "aws4auth-layer"
  compatible_runtimes = ["python3.11", "python3.10", "python3.9"]
  source_code_hash    = filebase64sha256("${var.layers_source_dir}/aws4auth-layer.zip")

  description = "AWS4Auth library for OpenSearch authentication"
}

resource "aws_lambda_layer_version" "opensearch" {
  filename            = "${var.layers_source_dir}/opensearch-py-layer.zip"
  layer_name          = "opensearch-py-layer"
  compatible_runtimes = ["python3.11", "python3.10", "python3.9"]
  source_code_hash    = filebase64sha256("${var.layers_source_dir}/opensearch-py-layer.zip")

  description = "OpenSearch Python client library"
}
