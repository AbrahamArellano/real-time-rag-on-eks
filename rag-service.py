from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer
import logging
from typing import List
import schedule
import time
import threading
import requests
from opensearchpy import RequestsHttpConnection
from langchain.vectorstores import OpenSearchVectorSearch
from container.credentials import get_auth


# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = FastAPI()

# Hardcoded values
QDRANT_URL = "http://qdrant.default.svc.cluster.local:6333"
VLLM_URL = "http://vllm-mistral-inf2-serve-svc.default.svc.cluster.local:8000/v1/chat/completions"
MODEL_ID = '/data/model/neuron-mistral7bv0.3'

# Initialize Qdrant client and SentenceTransformer
qdrant_client = QdrantClient(QDRANT_URL)
model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')

## Initialize OpenSearch client
aws_region = "us-west-2"
CONNECTION_TIMEOUT = 1000
opensearch_index = "embedding"
opensearch_domain_endpoint = "https://m917wg2n8hi4xjg8nt9d.us-west-2.aoss.amazonaws.com"
http_auth = get_auth(aws_region)

docsearch = OpenSearchVectorSearch.from_documents(
    index_name=opensearch_index,
    documents=shards[0],
    embedding=embeddings,
    opensearch_url=opensearch_domain_endpoint,
    http_auth=http_auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    timeout=CONNECTION_TIMEOUT
)

class ChatCompletionRequest(BaseModel):
    messages: List[dict]
    model: str

def get_context(query: str, limit: int = 3, similarity_threshold: float = 0.7) -> str:
    query_embedding = model.encode(query)
    search_results = qdrant_client.search(
        collection_name="pdf_embeddings",
        query_vector=query_embedding,
        limit=limit,
        score_threshold=similarity_threshold
    )
    
    contexts = []
    for hit in search_results:
        contexts.append(f"{hit.payload['text']}")
    
    return "\n\n".join(contexts) if contexts else ""

@app.post("/v1/chat/completions")
async def chat_completions(request: ChatCompletionRequest):
    try:
        user_query = request.messages[-1]['content']
        logger.info(f"Received query: {user_query}")
        context = get_context(user_query)
        logger.info(f"Retrieved context: {context}")

        if context:
            system_message = "You are an AI assistant that provides information about SkyWing Airways based on the given context. For questions about SkyWing Airways, use only the information provided in the context. For general questions not related to SkyWing Airways, provide answers based on your general knowledge."
            prompt = f"Context about SkyWing Airways:\n{context}\n\nHuman: {user_query}\n\nAssistant: I'll answer the question based on the context if it's about SkyWing Airways, or use my general knowledge for other topics."
        else:
            system_message = "You are an AI assistant that can answer both general questions and questions about SkyWing Airways. For SkyWing Airways questions, clearly state if you don't have specific information. For general questions, use your broad knowledge to provide accurate answers."
            prompt = f"Human: {user_query}\n\nAssistant: I'll answer your question to the best of my ability. If it's about SkyWing Airways and I don't have specific information, I'll let you know."

        vllm_request = {
            "model": request.model,
            "messages": [
                {"role": "system", "content": system_message},
                {"role": "user", "content": prompt}
            ]
        }

        logger.info(f"Sending request to VLLM: {vllm_request}")

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(VLLM_URL, json=vllm_request, timeout=30.0)
        
        response.raise_for_status()
        vllm_response = response.json()
        
        logger.info(f"VLLM response: {vllm_response}")
        
        assistant_response = vllm_response['choices'][0]['message']['content']
        
        return {"response": assistant_response}

    except httpx.ReadTimeout:
        logger.error("Timeout while connecting to VLLM service")
        raise HTTPException(status_code=504, detail="VLLM service timed out")
    except httpx.HTTPStatusError as e:
        logger.error(f"HTTP error from VLLM service: {e.response.status_code} - {e.response.text}")
        raise HTTPException(status_code=e.response.status_code, detail=f"Error from VLLM service: {e.response.text}")
    except Exception as e:
        logger.exception("Error in chat_completions endpoint")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/v1/models")
async def list_models():
    logger.info("Received request for model list")
    return {
        "object": "list",
        "data": [
            {
                "id": MODEL_ID,
                "object": "model",
                "owned_by": "organization",
                "permission": []
            }
        ]
    }

def consistency_check():
    test_questions = [
        "What is the baggage allowance for Economy Class?",
        "How many destinations does SkyWing Airways serve in North America?",
    ]
    
    for question in test_questions:
        response = requests.post(
            "http://vllm-mistral-inf2-serve-svc.default.svc.cluster.local:8000/v1/chat/completions",
            json={
                "messages": [{"role": "user", "content": question}],
                "model": MODEL_ID
            }
        )
        logger.info(f"Consistency check - Question: {question}")
        logger.info(f"Response: {response.json()['response']}")

# Run the consistency check every 6 hours
schedule.every(6).hours.do(consistency_check)

def run_schedule():
    while True:
        schedule.run_pending()
        time.sleep(1)

if __name__ == "__main__":
    schedule_thread = threading.Thread(target=run_schedule)
    schedule_thread.start()
    
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)