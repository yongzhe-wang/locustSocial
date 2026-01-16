import os
import httpx
import json
from dotenv import load_dotenv

load_dotenv()

key = os.environ.get("COHERE_API_KEY")
print(f"Key: {key[:5]}...")

url = "https://api.cohere.com/v2/embed"
headers = {
    "Authorization": f"Bearer {key}",
    "Content-Type": "application/json",
    "User-Agent": "python-requests/2.31.0" # Mimic requests
}

# Test 1: texts parameter (simple)
payload_texts = {
    "texts": ["hello world"],
    "model": "embed-english-v3.0",
    "input_type": "search_document",
    "embedding_types": ["float"]
}

print("\n--- Test 1: texts parameter ---")
try:
    resp = httpx.post(url, json=payload_texts, headers=headers)
    print(f"Status: {resp.status_code}")
    if resp.status_code != 200:
        print(f"Response: {resp.text[:200]}")
    else:
        print("Success!")
except Exception as e:
    print(f"Error: {e}")

# Test 2: inputs parameter (v2 style)
payload_inputs = {
    "inputs": [
        {
            "content": [
                {"type": "text", "text": "hello world"}
            ]
        }
    ],
    "model": "embed-english-v3.0",
    "input_type": "search_document",
    "embedding_types": ["float"]
}

print("\n--- Test 2: inputs parameter ---")
try:
    resp = httpx.post(url, json=payload_inputs, headers=headers)
    print(f"Status: {resp.status_code}")
    if resp.status_code != 200:
        print(f"Response: {resp.text[:200]}")
    else:
        print("Success!")
except Exception as e:
    print(f"Error: {e}")
