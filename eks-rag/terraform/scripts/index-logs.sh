#!/bin/bash
set -e

echo "=========================================="
echo "Indexing Logs to OpenSearch"
echo "=========================================="

# Validate environment variables
if [ -z "$OPENSEARCH_ENDPOINT" ] || [ -z "$COLLECTION_NAME" ] || [ -z "$AWS_REGION" ] || [ -z "$SCRIPTS_PATH" ]; then
    echo "Error: Required environment variables not set"
    echo "  OPENSEARCH_ENDPOINT: $OPENSEARCH_ENDPOINT"
    echo "  COLLECTION_NAME: $COLLECTION_NAME"
    echo "  AWS_REGION: $AWS_REGION"
    echo "  SCRIPTS_PATH: $SCRIPTS_PATH"
    exit 1
fi

echo "OpenSearch Endpoint: $OPENSEARCH_ENDPOINT"
echo "Collection Name: $COLLECTION_NAME"
echo "AWS Region: $AWS_REGION"
echo "Scripts Path: $SCRIPTS_PATH"

# Change to scripts directory
cd $SCRIPTS_PATH

# Check if error_logs.json exists
if [ ! -f "error_logs.json" ]; then
    echo "Error: error_logs.json not found. Please run generate_logs.py first."
    exit 1
fi

echo ""
echo "Indexing logs with embeddings (this may take several minutes)..."
echo "This process will:"
echo "  1. Create the OpenSearch index with vector mappings"
echo "  2. Generate embeddings using Bedrock Cohere model"
echo "  3. Index all logs with their embeddings"
echo ""

# Run the indexing script
python3 index_logs.py

if [ $? -ne 0 ]; then
    echo "Error: Failed to index logs"
    exit 1
fi

echo ""
echo "=========================================="
echo "Indexing Complete!"
echo "=========================================="
