# OpenSearch Index Creation with knn_vector Mapping using awscurl

# Wait for data access policy to propagate (5 minutes)
resource "time_sleep" "wait_for_policy_propagation" {
  create_duration = "300s"  # 5 minutes for policy to fully propagate to data plane

  triggers = {
    policy_id = var.data_access_policy_id
  }
}

resource "null_resource" "create_index" {
  triggers = {
    opensearch_endpoint = var.opensearch_endpoint
    index_name          = var.index_name
    policy_id           = var.data_access_policy_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      echo "=========================================="
      echo "OpenSearch Index Creation"
      echo "=========================================="
      echo "Endpoint: ${var.opensearch_endpoint}"
      echo "Index: ${var.index_name}"
      echo "Region: ${var.aws_region}"
      echo ""

      # Install awscurl if not available
      if ! command -v awscurl &> /dev/null; then
        echo "Installing awscurl..."
        pip3 install --break-system-packages awscurl || pip3 install awscurl || pipx install awscurl
      fi

      # Test connectivity first
      echo "Testing OpenSearch endpoint connectivity..."
      RESPONSE=$(awscurl --service aoss --region ${var.aws_region} \
        -X GET "https://${var.opensearch_endpoint}/" 2>&1) || {
        echo "❌ Failed to connect to OpenSearch endpoint"
        echo "Response: $RESPONSE"
        exit 1
      }

      echo "✅ Successfully connected to OpenSearch"

      # Check if index already exists
      echo "Checking if index '${var.index_name}' exists..."
      INDEX_EXISTS=$(awscurl --service aoss --region ${var.aws_region} \
        -X GET "https://${var.opensearch_endpoint}/${var.index_name}" 2>&1 | grep -q "error" && echo "false" || echo "true")

      if [ "$INDEX_EXISTS" = "true" ]; then
        echo "⚠️  Index '${var.index_name}' already exists, skipping creation"
        exit 0
      fi

      # Create index with full mapping
      echo "Creating index '${var.index_name}' with knn_vector mapping..."
      awscurl --service aoss --region ${var.aws_region} \
        -X PUT "https://${var.opensearch_endpoint}/${var.index_name}" \
        -H "Content-Type: application/json" \
        -d '{
          "mappings": {
            "properties": {
              "timestamp": {"type": "date"},
              "level": {"type": "keyword"},
              "service": {"type": "keyword"},
              "error_code": {"type": "keyword"},
              "message": {"type": "text"},
              "vehicle_id": {"type": "keyword"},
              "vehicle_state": {"type": "keyword"},
              "location": {
                "properties": {
                  "latitude": {"type": "float"},
                  "longitude": {"type": "float"}
                }
              },
              "sensor_readings": {
                "properties": {
                  "engine_temp": {"type": "float"},
                  "battery_voltage": {"type": "float"},
                  "fuel_pressure": {"type": "float"},
                  "speed": {"type": "float"},
                  "battery_level": {"type": "float"}
                }
              },
              "diagnostic_info": {
                "properties": {
                  "dtc_codes": {"type": "keyword"},
                  "system_status": {"type": "keyword"},
                  "last_maintenance": {"type": "date"}
                }
              },
              "metadata": {
                "properties": {
                  "environment": {"type": "keyword"},
                  "region": {"type": "keyword"},
                  "firmware_version": {"type": "keyword"}
                }
              },
              "message_embedding": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                  "engine": "faiss",
                  "name": "hnsw"
                }
              }
            }
          },
          "settings": {
            "index": {
              "knn": true
            }
          }
        }'

      echo ""
      echo "✅ Index '${var.index_name}' created successfully"
      echo "=========================================="
    EOT
  }

  depends_on = [time_sleep.wait_for_policy_propagation]
}
