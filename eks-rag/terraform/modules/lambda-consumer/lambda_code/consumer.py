import json
import base64
import os
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

# Configuration from environment variables
OPENSEARCH_ENDPOINT = os.environ['OPENSEARCH_ENDPOINT']
INDEX_NAME = os.environ.get('INDEX_NAME', 'error-logs-mock')
# AWS_REGION is automatically provided by Lambda runtime
AWS_REGION = os.environ.get('AWS_REGION', 'us-west-2')

# Initialize clients
bedrock = boto3.client('bedrock-runtime', region_name=AWS_REGION)

def get_opensearch_client():
    """Initialize OpenSearch client with IAM authentication"""
    credentials = boto3.Session().get_credentials()

    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        AWS_REGION,
        'aoss',
        session_token=credentials.token
    )

    client = OpenSearch(
        hosts=[{'host': OPENSEARCH_ENDPOINT, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=60
    )

    return client

def generate_embedding(text):
    """Generate embedding using Bedrock Cohere model"""
    try:
        response = bedrock.invoke_model(
            modelId="cohere.embed-english-v3",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "texts": [text],
                "input_type": "search_document"
            })
        )
        embedding = json.loads(response['body'].read())['embeddings'][0]
        return embedding
    except Exception as e:
        print(f"Error generating embedding: {e}")
        return None

def lambda_handler(event, context):
    """
    Lambda handler triggered by Kinesis
    Processes Kinesis stream records, generates embeddings, and indexes to OpenSearch
    """

    print(f"Received event with {len(event['Records'])} records")

    os_client = get_opensearch_client()

    total_processed = 0
    total_indexed = 0
    total_failed = 0

    # Process Kinesis records
    for record in event['Records']:
        try:
            # Decode Kinesis message
            message_bytes = base64.b64decode(record['kinesis']['data'])
            log = json.loads(message_bytes.decode('utf-8'))

            total_processed += 1

            # Generate embedding for the error message
            embedding = generate_embedding(log['message'])

            if embedding:
                log['message_embedding'] = embedding

                # Index to OpenSearch
                try:
                    response = os_client.index(
                        index=INDEX_NAME,
                        body=log
                    )
                    total_indexed += 1

                    if total_indexed % 10 == 0:
                        print(f"✅ Indexed {total_indexed} documents...")

                except Exception as e:
                    total_failed += 1
                    print(f"❌ Error indexing document: {e}")
            else:
                total_failed += 1
                print(f"❌ Failed to generate embedding for vehicle {log.get('vehicle_id', 'unknown')}")

        except Exception as e:
            total_failed += 1
            print(f"❌ Error processing record: {e}")

    print(f"\n📊 Completed: {total_processed} processed, {total_indexed} indexed, {total_failed} failed")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': total_processed,
            'indexed': total_indexed,
            'failed': total_failed
        })
    }
