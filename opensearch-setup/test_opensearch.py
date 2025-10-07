import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
import json
from opensearchpy import __versionstr__

print(f"OpenSearch Python client version: {__versionstr__}")

def get_opensearch_client(collection_endpoint):
    credentials = boto3.Session().get_credentials()
    region = 'us-west-2'
    
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

def main():
    collection_endpoint = 'ptd7yjca8ylq619uzv9e.us-west-2.aoss.amazonaws.com'
    client = get_opensearch_client(collection_endpoint)
    
    # Test 1: Check if index exists
    print("\n1 - Index info:")
    print(json.dumps(client.indices.get('error-logs-mock'), indent=2))
    
    # Test 2: Get mapping
    print("\n2 - Index mapping:")
    print(json.dumps(client.indices.get_mapping(index='error-logs-mock'), indent=2))
    
    # Test 3: Get document count
    print("\n3 - Document count:")
    print(json.dumps(client.count(index='error-logs-mock'), indent=2))
    
    # Test 4: Basic search with limited output
    print("\n4 - Basic search for 'engine temperature' (showing first 3 results):")
    search_response = client.search(
        index='error-logs-mock',
        body={
            "size": 3,
            "query": {
                "match": {
                    "message": "engine temperature"
                }
            }
        }
    )
    
    formatted_response = {
        "total_hits": search_response["hits"]["total"]["value"],
        "max_score": search_response["hits"]["max_score"],
        "took_ms": search_response["took"],
        "results": [format_search_hit(hit) for hit in search_response["hits"]["hits"]]
    }
    
    print(json.dumps(formatted_response, indent=2))
    
    # Test 5: Vector search
    print("\n5 - Vector search test:")
    test_embedding = get_test_embedding("engine malfunction high temperature")
    if test_embedding:
        vector_search_response = client.search(
            index='error-logs-mock',
            body={
                "size": 5,
                "_source": ["message", "service", "error_code", "vehicle_id", "sensor_readings"],
                "query": {
                    "knn": {
                        "message_embedding": {
                            "vector": test_embedding,
                            "k": 5
                        }
                    }
                }
            }
        )
        print(json.dumps(vector_search_response, indent=2))

def get_test_embedding(text="engine malfunction high temperature"):
    """Generate a real embedding for testing"""
    try:
        bedrock = boto3.client('bedrock-runtime', region_name='us-west-2')
        response = bedrock.invoke_model(
            modelId="cohere.embed-english-v3",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "texts": [text],
                "input_type": "search_query"
            })
        )
        return json.loads(response['body'].read())['embeddings'][0]
    except Exception as e:
        print(f"Error generating test embedding: {e}")
        return None

def format_search_hit(hit):
    """Format a search hit to show IoT vehicle fields"""
    return {
        "score": hit["_score"],
        "message": hit["_source"]["message"],
        "service": hit["_source"]["service"],
        "error_code": hit["_source"]["error_code"],
        "timestamp": hit["_source"]["timestamp"],
        "vehicle_id": hit["_source"].get("vehicle_id", "N/A"),
        "sensor_readings": hit["_source"].get("sensor_readings", {})
    }

if __name__ == "__main__":
    main()
