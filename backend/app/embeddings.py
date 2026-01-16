import base64
import io
from typing import Optional, Literal, List

import httpx
from PIL import Image
import time

from .settings import settings

COHERE_BASE = "https://api.cohere.com/v2"

def _to_data_uri(img_bytes: bytes) -> str:
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{b64}"

def cohere_embed(
    text: str,
    image_bytes_list: Optional[List[bytes]],
    input_type: Literal["search_document","search_query","classification","clustering"]="search_document",
    output_dimension: Optional[int] = None,
) -> List[float]:
    """
    Calls Cohere /embed with retries and honors 429 Retry-After.
    """
    if not settings.COHERE_API_KEY:
        raise RuntimeError("COHERE_API_KEY missing")

    content = []
    if text:
        content.append({"type":"text","text":text})
    if image_bytes_list:
        for img_bytes in image_bytes_list:
            content.append({"type":"image","image": _to_data_uri(img_bytes)})

    if not content:
        raise ValueError("empty input for embedding")

    payload = {
        "inputs": [{"content": content}],
        "model": settings.COHERE_EMBED_MODEL,
        "input_type": input_type,
        "embedding_types": ["float"],
    }
    if output_dimension:
        payload["output_dimension"] = output_dimension

    headers = {"Authorization": f"Bearer {settings.COHERE_API_KEY}"}

    # --- Retries with exponential backoff + Retry-After support ---
    max_attempts = 6
    base_delay = 0.5  # seconds
    last_err = None
    for attempt in range(1, max_attempts + 1):
        try:
            with httpx.Client(timeout=settings.COHERE_TIMEOUT) as client:
                r = client.post(f"{COHERE_BASE}/embed", json=payload, headers=headers)
            
            if r.status_code == 403:
                # User requested to hide this error (likely China IP ban). Return zero vector silently.
                return [0.0] * (output_dimension or settings.COHERE_EMBED_DIM)

            if r.status_code == 429:
                # honor Retry-After if present
                ra = r.headers.get("Retry-After")
                if ra:
                    try:
                        sleep_s = float(ra)
                    except ValueError:
                        sleep_s = base_delay * (2 ** (attempt - 1))
                else:
                    sleep_s = base_delay * (2 ** (attempt - 1))
                time.sleep(min(10.0, sleep_s))
                last_err = r.text
                continue
            r.raise_for_status()
            data = r.json()
            return data["embeddings"]["float"][0]
        except httpx.HTTPError as e:
            last_err = str(e)
            # backoff for transient 5xx as well
            if getattr(e, "response", None) and e.response is not None and e.response.status_code >= 500:
                time.sleep(min(10.0, base_delay * (2 ** (attempt - 1))))
                continue
            # non-retryable (4xx other than 429)
            break

    raise RuntimeError(f"Cohere embed failed after retries: {last_err}")
