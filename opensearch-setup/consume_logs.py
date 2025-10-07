import json
import boto3
from kafka import KafkaConsumer
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

# MSK Cluster ARN; replace with your own ARN
MSK_CLUSTER_ARN = "arn:aws:kafka:us-west-2:XXXXXXXXXX:cluster/streaming-data-ingestor/e07898e4-zzzz-xxxx-yyyy-293089f2a21f-s2"

# Kafka topic to consume from
TOPIC_NAME = "random-logs"

# Consumer Group ID
GROUP_ID = "kubecon-demo-log-group"

# IAM-based authentication token provider
class MSKTokenProvider():
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token('us-west-2')
        return token

token_provider = MSKTokenProvider()

def get_msk_bootstrap_brokers():
    """Fetches MSK bootstrap broker URLs with IAM authentication enabled."""
    client = boto3.client('kafka')
    response = client.get_bootstrap_brokers(ClusterArn=MSK_CLUSTER_ARN)
    return response["BootstrapBrokerStringSaslIam"]

def lambda_handler(event, context):
    """AWS Lambda function to consume Kafka messages from MSK."""
    bootstrap_servers = get_msk_bootstrap_brokers()

    # Create Kafka Consumer
    consumer = KafkaConsumer(
        TOPIC_NAME,
        bootstrap_servers=bootstrap_servers,
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=token_provider,
        group_id=GROUP_ID,
        auto_offset_reset="earliest",
        enable_auto_commit=True
    )

    messages = []

    try:
        # Consume a batch of messages using poll() with timeout
        records = consumer.poll(timeout_ms=30000)  # Wait for messages for up to 5 seconds
        for _, messages_list in records.items():
            for message in messages_list[:5]:  # Only process 5 messages
                log_entry = message.value.decode('utf-8')
                messages.append(log_entry)

        index_messages(messages)

    finally:
        # Ensure Kafka consumer is properly closed
        consumer.close()

    return {
        "statusCode": 200,
        "body": json.dumps({"logs": messages})
    }

def index_messages(messages):
    try:
        # Initialize clients
        bedrock = boto3.client('bedrock-runtime', region_name='us-west-2')
        opensearch_client = boto3.client('opensearchserverless')
        collection_name = 'error-logs-mock'
        index_name = 'error-logs-mock'
        # Get collection endpoint
        collection_endpoint = get_collection_endpoint(opensearch_client, collection_name)
        
        # Initialize OpenSearch client
        os_client = get_opensearch_client(collection_endpoint)

        for message in messages:
            log = json.loads(message)
            embedding = generate_embedding(bedrock, log['message'])
            if embedding:
                log['message_embedding'] = embedding
                try:
                    os_client.index(
                        index=index_name,
                        body=log
                    )
                except Exception as e:
                    print(f"Error indexing log: {e}")
    except Exception as e:
        print(f"Error in main: {str(e)}")
        raise

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

def get_opensearch_client(collection_endpoint):
    credentials = boto3.Session().get_credentials()
    region = 'us-west-2'
    
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        'aoss',  # Use 'aoss' for OpenSearch Serverless
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