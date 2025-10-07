import pprint
import gradio as gr
import requests
import json
import logging
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


RAG_SERVICE_URL = f"http://{os.environ.get('RAG_SERVICE_HOST', 'eks-rag-service')}/submit_query"


# Send query to RAG service
def send_query(query):
    logger.info(f"Sending query: {query}")
    try:
        payload = {
            "query": query
        }
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "text/event-stream"
        }
        
        # amazonq-ignore-next-line
        response = requests.post(RAG_SERVICE_URL,
                                 headers=headers,
                                 data=json.dumps(payload),
                                 stream=True)
        response.raise_for_status()
        
        # Process the streaming response
        full_response = ""
        for line in response.iter_lines():
            if line:
                # Decode the line and remove "data: " prefix if present
                decoded_line = line.decode('utf-8')
                if decoded_line.startswith("data: "):
                    decoded_line = decoded_line[6:]
                
                try:
                    # Parse the JSON response
                    json_response = json.loads(decoded_line)
                    # Extract and append the LLM response
                    if 'llm_response' in json_response:
                        full_response += json_response['llm_response']
                except json.JSONDecodeError:
                    # If not JSON, append the raw text
                    full_response += decoded_line
                
        return full_response
    
    except requests.RequestException as e:
        error_msg = f"Error: {str(e)}\nResponse content: {response.text if 'response' in locals() else 'No response'}"
        logger.error(error_msg)
        return error_msg

# Default prompts for testing
default_prompts = [
    "Are there any vehicles reporting engine temperatures above 110°C in the last hour? If yes, what immediate actions should be taken based on the sensor readings and diagnostic codes?",
    "Show me any vehicles with battery voltage below 11.5V that are currently in MOVING state. What should be communicated to the drivers?",
    "Are there any vehicles showing transmission failure codes P0700 in the last 30 minutes?",
]

iface = gr.Interface(
    fn=send_query,
    inputs=gr.components.Textbox(
        lines=3, 
        placeholder="Enter your question here...",
        label="Question"
    ),
    outputs=gr.components.Textbox(lines=10, label="Answer"),
    title="AI Assistant",
    description="Ask questions about the system being observed! (Responses will stream in real-time)",
    examples=[[prompt] for prompt in default_prompts],
    theme="default"
)

if __name__ == "__main__":
    iface.launch(server_name="0.0.0.0", server_port=7860)
