import os
import cohere
from dotenv import load_dotenv

load_dotenv()

key = os.environ.get("COHERE_API_KEY")
print(f"Key: {key[:5]}...")

try:
    co = cohere.ClientV2(api_key=key)
    print("Client created.")

    print("Embedding...")
    response = co.embed(
        texts=["hello world"],
        model="embed-english-v3.0",
        input_type="search_document",
        embedding_types=["float"]
    )
    print("Success!")
    print(response)

except Exception as e:
    print(f"Error: {e}")
