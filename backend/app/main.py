# app/main.py
from typing import List
from fastapi import (
    FastAPI,
    UploadFile,
    File,
    Form,
    BackgroundTasks,
    HTTPException,
    Request,
)
from fastapi.middleware.cors import CORSMiddleware
import psycopg2.extras
from .settings import settings
from .db import conn, ensure_pgvector_extension
from .embeddings import cohere_embed
from .utils import clean_text
from .models import PostOut, ErrorOut
from .models import UserEventIn, AdaptContentRequest, AdaptContentResponse
import google.generativeai as genai
from .features.posts import _compute_and_save_embedding
from .features.interactions import _fetch_recent_event_vectors,  _ensure_user, _resolve_post_id,_event_weight, _compute_weighted_profile,_maybe_recompute_user_embedding,upsert_user_embedding, fetch_user_liked_posts_content
from .features.recommendation import get_recommendations
from .firebase_setup import get_firestore_db
from apscheduler.schedulers.asyncio import AsyncIOScheduler
# --- NEW: simple embedding job queue to prevent API bursts ---
import threading, queue, time, base64

app = FastAPI(title="Embeddings API")

# --- Gemini Setup ---
if settings.GEMINI_API_KEY:
    genai.configure(api_key=settings.GEMINI_API_KEY)

# --- CORS ---
allow_origins = (
    [o.strip() for o in settings.CORS_ALLOW_ORIGINS.split(",")]
    if settings.CORS_ALLOW_ORIGINS != "*"
    else ["*"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------- Embedding worker ----------------
_embed_jobs: "queue.Queue[tuple[int, str | None, list[bytes] | None]]" = queue.Queue(maxsize=1000)

def _embed_worker(qps: float = 2.0):
    """
    Single-threaded worker to serialize calls to Cohere and respect a crude QPS.
    """
    min_interval = 1.0 / max(0.1, qps)
    last_call = 0.0
    while True:
        try:
            post_id, text, img_bytes_list = _embed_jobs.get()
            now = time.time()
            if now - last_call < min_interval:
                time.sleep(min_interval - (now - last_call))
            try:
                print(f"[worker] embedding job start post_id={post_id}")
                _compute_and_save_embedding(post_id, None, text or "", img_bytes_list)
                print(f"[worker] embedding job done post_id={post_id}")
            except Exception as e:
                print(f"[embed-worker] job failed post_id={post_id}: {e}")
            
            # Force 1s sleep after each job as requested
            time.sleep(1.0)
            last_call = time.time()
        except Exception as e:
            print(f"[embed-worker] loop error: {e}")

_worker_started = False
_worker_lock = threading.Lock()

def _ensure_worker():
    global _worker_started
    with _worker_lock:
        if not _worker_started:
            t = threading.Thread(target=_embed_worker, args=(2.0,), daemon=True)
            t.start()
            _worker_started = True
            print("[startup] embed worker started")

# --- Startup ---
scheduler = AsyncIOScheduler()

@app.on_event("startup")
async def _startup():
    ensure_pgvector_extension()
    _ensure_worker()
    
    scheduler.start()
    
    print("[startup] pgvector ensured, worker online")

@app.on_event("shutdown")
async def _shutdown():
    scheduler.shutdown()

@app.get("/healthz")
def healthz():
    return {"ok": True}



# --- Helper: verify shared secret from Functions (optional) ---
def _verify_webhook_secret(req: Request):
    expected = getattr(settings, "FIREBASE_WEBHOOK_SECRET", None)
    if expected:
        got = req.headers.get("x-firebase-token")
        if got != expected:
            print("[auth] webhook secret mismatch")
            raise HTTPException(status_code=403, detail="forbidden")
        else:
            print("[auth] webhook secret ok")

# --- Create / upsert post coming from Firebase (multipart/form-data) ---
@app.post("/api/posts", response_model=PostOut, responses={400: {"model": ErrorOut}})
async def create_post(
    request: Request,
    bg: BackgroundTasks,
    firebase_id: str | None = Form(None),
    title: str = Form(""),
    body: str | None = Form(""),
    images: list[UploadFile] = File(None),
    # NEW: allow fallback base64 sent by Functions if multipart image can’t attach
    images_b64: list[str] = Form(None),
):
    _verify_webhook_secret(request)
    print(f"[posts] incoming firebase_id={firebase_id} title_len={len(title or '')} body_len={len(body or '')}")

    text = clean_text(body or "")
    img_bytes_list: list[bytes] = []

    if images:
        for image in images:
            data = await image.read()
            print(f"[posts] image multipart bytes={len(data)}")
            if len(data) > settings.MAX_IMAGE_BYTES:
                raise HTTPException(status_code=400, detail="image too large")
            img_bytes_list.append(data)
    elif images_b64:
        for b64 in images_b64:
            try:
                if b64.startswith("data:"):
                    b64 = b64.split(",", 1)[1]
                    print("[posts] data URI detected for image_b64")
                data = base64.b64decode(b64)
                print(f"[posts] image_b64 bytes={len(data)}")
                if len(data) > settings.MAX_IMAGE_BYTES:
                    raise HTTPException(status_code=400, detail="image too large")
                img_bytes_list.append(data)
            except Exception:
                raise HTTPException(status_code=400, detail="bad image_b64")

    # insert / upsert
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        if firebase_id:
            cur.execute(
                """
                INSERT INTO posts (firebase_id, title, body)
                VALUES (%s, %s, %s)
                ON CONFLICT (firebase_id)
                DO UPDATE SET
                    title = EXCLUDED.title,
                    body  = EXCLUDED.body
                RETURNING id, title, body
                """,
                (firebase_id, title, text),
            )
        else:
            cur.execute(
                "INSERT INTO posts(title, body) VALUES(%s,%s) RETURNING id, title, body",
                (title, text),
            )
        row = cur.fetchone()
    print(f"[posts] upserted post id={row['id']}")

    # enqueue embedding job instead of firing many parallel background tasks
    try:
        _embed_jobs.put_nowait((row["id"], text, img_bytes_list))
        print(f"[posts] queued embedding job post_id={row['id']}")
    except queue.Full:
        print("[posts] embed queue full, scheduling inline background task")
        bg.add_task(_compute_and_save_embedding, row["id"], firebase_id, text, img_bytes_list)

    return PostOut(id=row["id"], title=row["title"], body=row["body"])

# -------------------- USER EVENTS & EMBEDDINGS --------------------



@app.post("/api/user-event")
def user_event(evt: UserEventIn, request: Request, bg: BackgroundTasks):
    _verify_webhook_secret(request)
    print(f"[event] receive uid={evt.uid} etype={evt.etype} fpid={evt.firebase_post_id} pid={evt.post_id} w={evt.weight}")

    pid = _resolve_post_id(evt.firebase_post_id, evt.post_id)
    _ensure_user(evt.uid)
    w = _event_weight(evt.etype, evt.weight)

    with conn() as c, c.cursor() as cur:
        cur.execute(
            "INSERT INTO user_events(uid, post_id, etype, weight) VALUES(%s,%s,%s,%s)",
            (evt.uid, pid, evt.etype, w),
        )
    print(f"[event] inserted user_event uid={evt.uid} post_id={pid} etype={evt.etype} weight={w}")

    # let the worker batch naturally; no need to flood
    bg.add_task(_maybe_recompute_user_embedding, evt.uid)
    print(f"[event] scheduled maybe_recompute for uid={evt.uid}")
    return {"ok": True}


@app.post("/api/users/{uid}/embedding/recompute")
def recompute_user_embedding(uid: str, k: int = 30):
    return upsert_user_embedding(uid, k=k)

@app.get("/api/users/{uid}/embedding")
def get_user_embedding(uid: str):
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT uid, examples_count, updated_at, embedding_model, embedding_version "
            "FROM user_embeddings WHERE uid = %s",
            (uid,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="embedding not found")
    print(f"[profile] get_user_embedding uid={uid} examples_count={row['examples_count']}")
    return row
import random
import psycopg2.extras
from typing import List, Any
import json
from fastapi import HTTPException

@app.get("/api/rank")
def rank(uid: str, limit: int = 15, cursor: int = 0):
    """
    Recommend posts for a user, combining:
      - user embedding similarity
      - freshness (newer posts slightly favored)
      - global popularity via like counts
    """
    return get_recommendations(uid, limit, cursor)

@app.post("/api/adapt-content", response_model=AdaptContentResponse)
async def adapt_content(req: AdaptContentRequest):
    if not settings.GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Gemini API key not configured")
        
    # Use gemini-2.0-flash for better availability and speed
    model = genai.GenerativeModel("gemini-2.0-flash")
    
    style_context = ""
    if req.uid:
        try:
            liked_posts = fetch_user_liked_posts_content(req.uid, limit=3)
            if liked_posts:
                # Truncate to avoid huge prompts, just take first 200 chars of each
                examples = "\n".join([f"- {post[:200]}..." for post in liked_posts])
                style_context = f"""
    User's preferred content style (based on liked posts):
    {examples}
    
    Please adapt the text to match this style preference where appropriate, while maintaining the requested '{req.style}' tone.
    """
        except Exception as e:
            print(f"[adapt] failed to fetch user history: {e}")
            # continue without personalization

    # Structured prompt for Fact Locking and Source Tracing
    title_instruction = ""
    input_title = ""
    if req.title:
        title_instruction = '- "adapted_title": The rewritten title.'
        input_title = f'Input Title: "{req.title}"'

    prompt = f"""
    You are a content adaptation assistant. 
    Task: Rewrite the following social media post to be more {req.style}.
    {style_context}
    
    CRITICAL RULES:
    1. FACT LOCKING: You must identify and PRESERVE all factual information (names, locations, prices, numbers, specific objects) exactly as they are. Do not change them.
    2. OPINION MODIFICATION: You may rewrite opinions, tone, and style to match the requested style ({req.style}).
    3. FORMATTING: You MUST preserve the original paragraph structure and line breaks. Use '\\n' for newlines in the JSON string. Do not output the text as a single block if the original had paragraphs.
    4. OUTPUT FORMAT: Return ONLY a valid JSON object with the following keys:
       - "adapted_text": The rewritten text.
       {title_instruction}
       - "facts": A list of strings containing the factual elements you preserved.
       - "modifications": A list of strings describing specific changes you made (e.g., "Changed 'good' to 'stunning'").
    
    {input_title}
    Input Text:
    \"\"\"
    {req.text}
    \"\"\"
    """
    
    try:
        response = await model.generate_content_async(prompt)
        
        # Clean up response to ensure it's valid JSON
        text_response = response.text.strip()
        if text_response.startswith("```json"):
            text_response = text_response[7:]
        if text_response.endswith("```"):
            text_response = text_response[:-3]
            
        import json
        data = json.loads(text_response)
        
        return AdaptContentResponse(
            adapted_text=data.get("adapted_text", ""),
            adapted_title=data.get("adapted_title"),
            facts=data.get("facts", []),
            modifications=data.get("modifications", [])
        )
    except Exception as e:
        print(f"Gemini error: {e}")
        # Fallback: Try to list models to see what's available for debugging
        try:
            for m in genai.list_models():
                if 'generateContent' in m.supported_generation_methods:
                    print(f"Available model: {m.name}")
        except:
            pass
            
        # Fallback if JSON parsing fails or API error
        raise HTTPException(status_code=500, detail=f"AI adaptation failed: {str(e)}")
