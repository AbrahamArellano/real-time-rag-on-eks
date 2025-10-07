# index_logs.py
import json
import os
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

def get_opensearch_client(collection_endpoint):
    credentials = boto3.Session().get_credentials()
    region = 'us-west-2'

    # Strip protocol if present (OpenSearch client expects just hostname)
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

    return client

def create_index_mapping(client, index_name):
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
                },
                "diagnostic_embedding": {
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
    print(f"Created index mapping for {index_name}")

def generate_embedding(bedrock, text):
    try:
        response = bedrock.invoke_model(
            modelId="cohere.embed-english-v3",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "texts": [text],
                "input_type": "search_query"
            })
        )
        embedding = json.loads(response['body'].read())['embeddings'][0]
        return embedding
    except Exception as e:
        print(f"Error generating embedding: {e}")
        return None

def prepare_diagnostic_text(diagnostic_info):
    dtc_codes = ' '.join(diagnostic_info.get('dtc_codes', []))
    return f"System Status: {diagnostic_info.get('system_status', '')} DTC Codes: {dtc_codes}"

def get_collection_endpoint(client, collection_name):
    print(f"Getting endpoint for collection {collection_name}...")
    
    collections = client.list_collections(
        collectionFilters={'name': collection_name}
    )['collectionSummaries']
    
    if not collections:
        raise ValueError(f"Collection {collection_name} not found")
        
    collection_id = collections[0]['id']
    
    response = client.batch_get_collection(
        ids=[collection_id]
    )
    
    if not response['collectionDetails']:
        raise ValueError(f"No details found for collection {collection_name}")
        
    endpoint = response['collectionDetails'][0]['collectionEndpoint']
    print(f"Found endpoint: {endpoint}")
    return endpoint.replace('https://', '')

def delete_index_if_exists(client, index_name):
    try:
        if client.indices.exists(index=index_name):
            print(f"Deleting existing index {index_name}...")
            client.indices.delete(index=index_name)
            print(f"Index {index_name} deleted successfully")
    except Exception as e:
        print(f"Error deleting index: {e}")

def main():
    try:
        # Initialize clients
        bedrock = boto3.client('bedrock-runtime', region_name='us-west-2')
        collection_name = 'error-logs-mock'

        # Get collection endpoint from environment variable (passed from Terraform)
        # If not provided, fall back to API discovery
        collection_endpoint_env = os.environ.get('OPENSEARCH_ENDPOINT')

        if collection_endpoint_env:
            # Use provided endpoint directly
            if not collection_endpoint_env.startswith('http'):
                collection_endpoint = f"https://{collection_endpoint_env}"
            else:
                collection_endpoint = collection_endpoint_env
            print(f"Using provided endpoint: {collection_endpoint}")
        else:
            # Fall back to API discovery
            print(f"No endpoint provided, discovering via API...")
            opensearch_client = boto3.client('opensearchserverless')
            collection_endpoint = get_collection_endpoint(opensearch_client, collection_name)
        
        # Initialize OpenSearch client
        os_client = get_opensearch_client(collection_endpoint)
        
        # Delete existing index if it exists
        index_name = 'error-logs-mock'
        delete_index_if_exists(os_client, index_name)
        
        # Create new index with correct mapping
        print(f"Creating new index {index_name} with updated mapping...")
        create_index_mapping(os_client, index_name)
        
        # Load error logs
        with open('error_logs.json', 'r') as f:
            logs = json.load(f)
        
        # Index logs with embeddings
        print("Indexing logs with embeddings...")
        successful_indexes = 0
        
        for log in logs:
            # Generate embeddings for message and diagnostic info
            message_embedding = generate_embedding(bedrock, log['message'])
            diagnostic_text = prepare_diagnostic_text(log['diagnostic_info'])
            diagnostic_embedding = generate_embedding(bedrock, diagnostic_text)
            
            if message_embedding and diagnostic_embedding:
                log['message_embedding'] = message_embedding
                log['diagnostic_embedding'] = diagnostic_embedding
                try:
                    os_client.index(
                        index=index_name,
                        body=log
                    )
                    successful_indexes += 1
                    if successful_indexes % 10 == 0:
                        print(f"Successfully indexed {successful_indexes} documents...")
                except Exception as e:
                    print(f"Error indexing log: {e}")
        
        print(f"\nIndexing complete. Successfully indexed {successful_indexes} out of {len(logs)} logs")

        # Verify the index was created with correct mapping
        print("\nVerifying index mapping:")
        mapping = os_client.indices.get_mapping(index=index_name)
        print(json.dumps(mapping, indent=2))

    except Exception as e:
        print(f"Error in main: {str(e)}")
        raise

if __name__ == "__main__":
    main()
