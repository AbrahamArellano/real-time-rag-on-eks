# Install Python dependencies
resource "null_resource" "install_dependencies" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing Python dependencies..."
      pip3 install --user boto3 opensearch-py requests-aws4auth || pip3 install --break-system-packages boto3 opensearch-py requests-aws4auth
      echo "Dependencies installed"
    EOT
  }
}

# Generate sample logs
resource "null_resource" "generate_logs" {
  triggers = {
    collection_endpoint = var.opensearch_collection_endpoint
  }

  provisioner "local-exec" {
    command     = "python3 generate_logs.py"
    working_dir = "${path.root}/${var.scripts_path}"
  }

  depends_on = [null_resource.install_dependencies]
}

# Wait for OpenSearch collection to be fully ready
resource "null_resource" "wait_for_opensearch" {
  triggers = {
    collection_endpoint = var.opensearch_collection_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for OpenSearch collection to be ACTIVE..."
      echo "Collection endpoint: ${var.opensearch_collection_endpoint}"

      # Extract collection ID from endpoint (format: <id>.region.aoss.amazonaws.com)
      COLLECTION_ID=$(echo "${var.opensearch_collection_endpoint}" | cut -d'.' -f1)
      echo "Collection ID: $COLLECTION_ID"

      for i in {1..30}; do
        STATUS=$(aws opensearchserverless batch-get-collection \
          --ids $COLLECTION_ID \
          --region ${var.aws_region} \
          --query 'collectionDetails[0].status' \
          --output text 2>/dev/null || echo "NOT_FOUND")

        if [ "$STATUS" = "ACTIVE" ]; then
          echo "✓ Collection is ACTIVE"
          sleep 10  # Additional buffer for full availability
          exit 0
        fi

        echo "Attempt $i/30: Collection status is $STATUS, waiting 10s..."
        sleep 10
      done

      echo "Error: Collection did not become ACTIVE within 5 minutes"
      exit 1
    EOT
  }

  depends_on = [
    null_resource.install_dependencies,
    null_resource.generate_logs
  ]
}

# Index logs with embeddings
resource "null_resource" "index_logs" {
  triggers = {
    collection_endpoint = var.opensearch_collection_endpoint
    logs_generated      = null_resource.generate_logs.id
  }

  provisioner "local-exec" {
    command     = "${path.root}/scripts/index-logs.sh"
    working_dir = path.root
    environment = {
      OPENSEARCH_ENDPOINT = var.opensearch_collection_endpoint
      COLLECTION_NAME     = var.opensearch_collection_name
      AWS_REGION          = var.aws_region
      SCRIPTS_PATH        = "${path.root}/${var.scripts_path}"
    }
  }

  depends_on = [
    null_resource.install_dependencies,
    null_resource.generate_logs,
    null_resource.wait_for_opensearch
  ]
}
