# app/main.py
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
from .models import UserEventIn
from .features.posts import _compute_and_save_embedding
from .features.interactions import _fetch_recent_event_vectors,  _ensure_user, _resolve_post_id,_event_weight, _compute_weighted_profile,_maybe_recompute_user_embedding,upsert_user_embedding
# --- NEW: simple embedding job queue to prevent API bursts ---
import threading, queue, time, base64

app = FastAPI(title="LocustSocial API")

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
_embed_jobs: "queue.Queue[tuple[int, str | None, bytes | None]]" = queue.Queue(maxsize=1000)

def _embed_worker(qps: float = 2.0):
    """
    Single-threaded worker to serialize calls to Cohere and respect a crude QPS.
    """
    min_interval = 1.0 / max(0.1, qps)
    last_call = 0.0
    while True:
        try:
            post_id, text, img_bytes = _embed_jobs.get()
            now = time.time()
            if now - last_call < min_interval:
                time.sleep(min_interval - (now - last_call))
            try:
                print(f"[worker] embedding job start post_id={post_id}")
                _compute_and_save_embedding(post_id, None, text or "", img_bytes)
                print(f"[worker] embedding job done post_id={post_id}")
            except Exception as e:
                print(f"[embed-worker] job failed post_id={post_id}: {e}")
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
@app.on_event("startup")
def _startup():
    ensure_pgvector_extension()
    _ensure_worker()
    print("[startup] pgvector ensured & worker online")

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
    image: UploadFile | None = File(None),
    # NEW: allow fallback base64 sent by Functions if multipart image can’t attach
    image_b64: str | None = Form(None),
):
    _verify_webhook_secret(request)
    print(f"[posts] incoming firebase_id={firebase_id} title_len={len(title or '')} body_len={len(body or '')}")

    text = clean_text(body or "")
    img_bytes: bytes | None = None

    if image:
        data = await image.read()
        print(f"[posts] image multipart bytes={len(data)}")
        if len(data) > settings.MAX_IMAGE_BYTES:
            raise HTTPException(status_code=400, detail="image too large")
        img_bytes = data
    elif image_b64:
        try:
            b64 = image_b64
            if b64.startswith("data:"):
                b64 = b64.split(",", 1)[1]
                print("[posts] data URI detected for image_b64")
            data = base64.b64decode(b64)
            print(f"[posts] image_b64 bytes={len(data)}")
            if len(data) > settings.MAX_IMAGE_BYTES:
                raise HTTPException(status_code=400, detail="image too large")
            img_bytes = data
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
        _embed_jobs.put_nowait((row["id"], text, img_bytes))
        print(f"[posts] queued embedding job post_id={row['id']}")
    except queue.Full:
        print("[posts] embed queue full, scheduling inline background task")
        bg.add_task(_compute_and_save_embedding, row["id"], firebase_id, text, img_bytes)

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

POPULARITY_ALPHA = 0.3  # how strongly likes affect ranking


@app.get("/api/rank")
def rank(uid: str, limit: int = 15, cursor: int = 0):
    """
    Recommend posts for a user, combining:
      - user embedding similarity
      - freshness (newer posts slightly favored)
      - global popularity via like counts
    """
    limit = min(max(limit, 1), 200)
    offset = int(cursor)
    print(f"[rank] computing recommendations for uid={uid} limit={limit} offset={offset}")

    # 1) Load user embedding
    with conn() as c, c.cursor() as cur:
        cur.execute("SELECT embedding FROM user_embeddings WHERE uid = %s", (uid,))
        row = cur.fetchone()

    def coerce_embedding(x: Any) -> List[float] | None:
        if x is None:
            return None
        if isinstance(x, (list, tuple)):
            return [float(v) for v in x]
        if isinstance(x, str):
            try:
                parsed = json.loads(x)
                if isinstance(parsed, list):
                    return [float(v) for v in parsed]
            except Exception:
                pass
        return None

    uvec = coerce_embedding(row[0]) if row else None

    # Utility to fetch recent *popular* posts, used for cold-start + top-up
    def latest_posts_fbids(k: int, offset: int = 0) -> list[str]:
        if k <= 0:
            return []
        with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                WITH post_likes AS (
                  SELECT post_id, COUNT(*) AS likes
                  FROM user_events
                  WHERE etype = 'like'
                  GROUP BY post_id
                )
                SELECT p.firebase_id
                FROM posts p
                LEFT JOIN post_likes pl ON pl.post_id = p.id
                WHERE p.embedding IS NOT NULL
                  AND p.firebase_id IS NOT NULL
                ORDER BY
                  COALESCE(pl.likes, 0) DESC,
                  p.created_at DESC
                LIMIT %s OFFSET %s
                """,
                (k, offset),
            )
            return [r["firebase_id"] for r in cur.fetchall() if r["firebase_id"]]

    # 2) If user embedding missing → popularity + recency fallback
    if not uvec:
        print(f"[rank] no embedding for {uid}, returning popularity-weighted fallback")
        latest = latest_posts_fbids(limit, offset)
        random.shuffle(latest)
        next_cursor = offset + limit if len(latest) == limit else None
        return {"post_ids": latest, "next_cursor": next_cursor}

    # 3) Ranked query using pgvector + likes
    print(f"[rank] user embedding found, running similarity + likes query")
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        try:
            cur.execute("SET LOCAL ivfflat.probes = %s", (10,))
        except Exception:
            pass

        cur.execute(
            """
            WITH post_likes AS (
              SELECT post_id, COUNT(*) AS likes
              FROM user_events
              WHERE etype = 'like'
              GROUP BY post_id
            )
            SELECT p.firebase_id,
                   COALESCE(pl.likes, 0) AS likes
            FROM posts p
            LEFT JOIN post_likes pl ON pl.post_id = p.id
            WHERE p.embedding IS NOT NULL
              AND p.firebase_id IS NOT NULL
            ORDER BY
              -- similarity (lower is better)
              (p.embedding <=> (%s)::float4[]::vector)
              -- freshness penalty (caps at 0.15)
              + LEAST(
                  0.15,
                  GREATEST(
                    0.0,
                    (EXTRACT(EPOCH FROM (now() - p.created_at))/3600.0) * 0.002
                  )
                )
              -- popularity reward: more likes → lower score
              - %s * LN(1 + COALESCE(pl.likes, 0))
            LIMIT %s OFFSET %s
            """,
            (uvec, POPULARITY_ALPHA, limit, offset),
        )
        ranked_rows = cur.fetchall()

    ranked = [r["firebase_id"] for r in ranked_rows if r["firebase_id"]]

    # 4) Diversity: random but biased toward popular posts
    RANDOM_COUNT = min(5, limit)
    random_fbids: list[str] = []
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            WITH post_likes AS (
              SELECT post_id, COUNT(*) AS likes
              FROM user_events
              WHERE etype = 'like'
              GROUP BY post_id
            )
            SELECT p.firebase_id
            FROM posts p
            LEFT JOIN post_likes pl ON pl.post_id = p.id
            WHERE p.embedding IS NOT NULL
              AND p.firebase_id IS NOT NULL
            ORDER BY
              COALESCE(pl.likes, 0) DESC,
              RANDOM()
            LIMIT %s
            """,
            (limit * 3,),
        )
        pool = [r["firebase_id"] for r in cur.fetchall() if r["firebase_id"]]
        seen = set(ranked)
        for fbid in pool:
            if fbid not in seen:
                random_fbids.append(fbid)
                seen.add(fbid)
                if len(random_fbids) >= RANDOM_COUNT:
                    break

    merged = (random_fbids + [fbid for fbid in ranked if fbid not in random_fbids])[:limit]

    # 5) Top up if short
    if len(merged) < limit:
        topup = latest_posts_fbids(limit * 2, offset)
        seen = set(merged)
        for fbid in topup:
            if fbid not in seen:
                merged.append(fbid)
                if len(merged) >= limit:
                    break

    next_cursor = offset + limit if len(merged) == limit else None
    print(f"[rank] returning {len(merged)} posts next_cursor={next_cursor}")
    return {"post_ids": merged, "next_cursor": next_cursor}
