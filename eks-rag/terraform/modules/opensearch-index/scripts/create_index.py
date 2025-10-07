#!/usr/bin/env python3
"""
OpenSearch Index Creation Script
Creates error-logs-mock index with knn_vector mapping for vector search
"""
import json
import os
import sys
import time
import boto3
import subprocess
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

def get_opensearch_client(collection_endpoint, region, max_retries=20, retry_delay=30):
    """Initialize OpenSearch client with IAM authentication and DNS retry logic"""
    credentials = boto3.Session().get_credentials()

    # Strip protocol if present
    if collection_endpoint.startswith('https://'):
        collection_endpoint = collection_endpoint.replace('https://', '')
    if collection_endpoint.startswith('http://'):
        collection_endpoint = collection_endpoint.replace('http://', '')

    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        'aoss',
        session_token=credentials.token
    )

    client = OpenSearch(
        hosts=[{'host': collection_endpoint, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=60
    )

    # Retry connection with DNS resolution
    for attempt in range(1, max_retries + 1):
        try:
            # Test connection
            client.info()
            print(f"✅ Connected to OpenSearch (attempt {attempt})")
            return client
        except Exception as e:
            error_msg = str(e)
            if 'DNS resolution failure' in error_msg or '503' in error_msg or '404' in error_msg or 'NotFoundError' in str(type(e)):
                if attempt < max_retries:
                    print(f"⏳ Collection not ready (attempt {attempt}/{max_retries}), waiting {retry_delay}s...")
                    time.sleep(retry_delay)
                else:
                    print(f"❌ Collection not available after {max_retries} attempts")
                    raise
            else:
                raise

    return client

def create_index_mapping(client, index_name):
    """Create index with knn_vector mapping"""
    mapping = {
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
                "knn": True
            }
        }
    }

    client.indices.create(index=index_name, body=mapping)
    print(f"✅ Created index '{index_name}' with knn_vector mapping")

def wait_for_collection_active(collection_id, region, max_wait_minutes=15):
    """Wait for OpenSearch collection to be ACTIVE using AWS CLI"""
    print(f"⏳ Waiting for collection '{collection_id}' to be ACTIVE...")

    max_attempts = max_wait_minutes * 2  # Check every 30 seconds
    for attempt in range(1, max_attempts + 1):
        try:
            result = subprocess.run(
                ['aws', 'opensearchserverless', 'batch-get-collection',
                 '--ids', collection_id, '--region', region],
                capture_output=True,
                text=True,
                check=True
            )

            data = json.loads(result.stdout)
            if data.get('collectionDetails'):
                status = data['collectionDetails'][0].get('status')
                print(f"   Collection status: {status} (attempt {attempt}/{max_attempts})")

                if status == 'ACTIVE':
                    print(f"✅ Collection is ACTIVE")
                    return True
                elif status == 'FAILED':
                    print(f"❌ Collection creation FAILED")
                    return False

            time.sleep(30)
        except Exception as e:
            print(f"   Error checking status: {e}")
            time.sleep(30)

    print(f"❌ Collection did not become ACTIVE after {max_wait_minutes} minutes")
    return False

def main():
    """Main execution"""
    # Get configuration from environment variables
    collection_endpoint = os.environ.get('OPENSEARCH_ENDPOINT')
    index_name = os.environ.get('INDEX_NAME', 'error-logs-mock')
    region = os.environ.get('AWS_REGION', 'us-west-2')
    collection_id = os.environ.get('OPENSEARCH_COLLECTION_ID')

    if not collection_endpoint:
        print("❌ ERROR: OPENSEARCH_ENDPOINT environment variable not set")
        sys.exit(1)

    print(f"Creating OpenSearch index '{index_name}'...")
    print(f"OpenSearch endpoint: {collection_endpoint}")
    print(f"Region: {region}")

    # Extract collection ID from endpoint or use provided ID
    if collection_id:
        # Use provided collection ID
        collection_id_to_check = collection_id.split('/')[-1]
    else:
        # Extract ID from endpoint (first part before first dot)
        collection_id_to_check = collection_endpoint.replace('https://', '').split('.')[0]

    # Wait for collection to be ACTIVE
    if not wait_for_collection_active(collection_id_to_check, region):
        print("❌ Cannot proceed - collection not available")
        sys.exit(1)

    # AWS recommends waiting ~1 minute after ACTIVE for data access rules to propagate
    print("⏳ Waiting 90 seconds for endpoint to be fully ready...")
    time.sleep(90)
    print("✅ Wait complete, attempting connection...")

    try:
        # Initialize OpenSearch client
        client = get_opensearch_client(collection_endpoint, region)

        # Check if index exists
        if client.indices.exists(index=index_name):
            print(f"⚠️  Index '{index_name}' already exists")

            # Verify it has the correct mapping
            mapping = client.indices.get_mapping(index=index_name)
            if 'message_embedding' in mapping[index_name]['mappings']['properties']:
                embedding_type = mapping[index_name]['mappings']['properties']['message_embedding']['type']
                if embedding_type == 'knn_vector':
                    print(f"✅ Index has correct knn_vector mapping")
                    sys.exit(0)
                else:
                    print(f"❌ ERROR: message_embedding field exists but is type '{embedding_type}', not 'knn_vector'")
                    print("Please delete the index and re-run to create with correct mapping")
                    sys.exit(1)
            else:
                print(f"❌ ERROR: Index exists but missing 'message_embedding' field")
                print("Please delete the index and re-run to create with correct mapping")
                sys.exit(1)
        else:
            # Create index with mapping
            create_index_mapping(client, index_name)

            # Verify creation
            mapping = client.indices.get_mapping(index=index_name)
            print("\n✅ Index mapping verification:")
            print(json.dumps(mapping[index_name]['mappings']['properties']['message_embedding'], indent=2))

            print(f"\n✅ SUCCESS: Index '{index_name}' created and ready for vector search")
            sys.exit(0)

    except Exception as e:
        print(f"❌ ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
