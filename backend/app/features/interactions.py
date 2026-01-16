# app/features/interactions.py
from fastapi import HTTPException
from typing import Optional, Tuple, List
import psycopg2.extras
import numpy as np

from app.db import conn

# -------------------- FETCH RECENT EVENT VECTORS --------------------

def _fetch_recent_event_vectors(uid: str, k: int = 30) -> Tuple[List[List[float]], List[float]]:
    """
    Fetch the k most recent (weight, embedding) pairs for a user.
    IMPORTANT: cast pgvector -> float4[] so psycopg2 returns a Python list of floats
    instead of a string like "[0.123, ...]".
    """
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT
              ue.weight,
              (p.embedding)::float4[] AS embedding
            FROM user_events ue
            JOIN posts p ON p.id = ue.post_id
            WHERE ue.uid = %s
              AND p.embedding IS NOT NULL
            ORDER BY ue.ts DESC
            LIMIT %s
            """,
            (uid, k),
        )
        rows = cur.fetchall()

    if not rows:
        print(f"[profile] no rows for uid={uid}")
        return [], []

    # rows[i]["embedding"] is now a Python list[float]
    vecs = [list(map(float, r["embedding"])) for r in rows if r.get("embedding")]
    ws   = [float(r["weight"]) for r in rows if r.get("embedding")]
    print(f"[profile] fetched k={len(vecs)} rows for uid={uid}")
    return vecs, ws


# -------------------- USER / ID HELPERS --------------------

def _ensure_user(uid: str):
    with conn() as c, c.cursor() as cur:
        cur.execute(
            "INSERT INTO users(uid) VALUES(%s) ON CONFLICT (uid) DO NOTHING",
            (uid,),
        )
    print(f"[user] ensured uid={uid}")

def _resolve_post_id(firebase_post_id: str | None, post_id: int | None) -> int:
    if post_id:
        print(f"[event] resolved post_id directly id={post_id}")
        return post_id
    if not firebase_post_id:
        raise HTTPException(status_code=400, detail="post identifier required")
    with conn() as c, c.cursor() as cur:
        cur.execute("SELECT id FROM posts WHERE firebase_id = %s", (firebase_post_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="post not found")
        print(f"[event] resolved firebase_post_id={firebase_post_id} -> id={row[0]}")
        return row[0]

def _event_weight(etype: str, override: float | None) -> float:
    if override is not None:
        return float(override)
    return {
        "view": 1.0,
        "like": 3.0,
        "comment": 5.0,
        "share": 6.0,
    }.get(etype, 1.0)


# -------------------- PROFILE VECTOR --------------------

def _compute_weighted_profile(vectors: List[List[float]], weights: List[float]) -> Optional[List[float]]:
    if not vectors:
        return None
    V = np.array(vectors, dtype=np.float32)                    # [n, d]
    W = np.array(weights or [1.0] * len(vectors), dtype=np.float32)  # [n]
    # row-normalize each vector before weighting, so one long vector doesn't dominate
    norms = np.linalg.norm(V, axis=1, keepdims=True)           # [n, 1]
    norms[norms == 0.0] = 1.0
    Vn = V / norms
    q = (W[:, None] * Vn).sum(axis=0)                          # [d]
    q_norm = np.linalg.norm(q) or 1.0
    q /= q_norm
    return list(map(float, q))


# -------------------- UPSERT USER EMBEDDING --------------------

def _maybe_recompute_user_embedding(uid: str, k: int = 30, stride: int = 5):
    # only recompute every "stride" events to avoid thrashing
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT COUNT(*) AS n FROM user_events WHERE uid = %s", (uid,))
        n = cur.fetchone()["n"]

    if n % stride != 0:
        print(f"[profile] skip recompute uid={uid} count={n} stride={stride}")
        return

    vecs, ws = _fetch_recent_event_vectors(uid, k=k)
    profile = _compute_weighted_profile(vecs, ws)
    if profile is None:
        print(f"[profile] no eligible vectors to recompute uid={uid}")
        return

    with conn() as c, c.cursor() as cur:
        cur.execute(
            """
            INSERT INTO user_embeddings(uid, embedding, examples_count, updated_at)
            VALUES (%s, (%s)::float4[]::vector, %s, now())
            ON CONFLICT (uid) DO UPDATE
            SET embedding = EXCLUDED.embedding,
                examples_count = EXCLUDED.examples_count,
                updated_at = now()
            """,
            (uid, profile, len(vecs)),
        )
    print(f"[profile] upserted user_embeddings uid={uid} examples_count={len(vecs)}")

def upsert_user_embedding(uid: str, k: int = 30) -> dict:
    _ensure_user(uid)
    vecs, ws = _fetch_recent_event_vectors(uid, k=k)
    profile = _compute_weighted_profile(vecs, ws)
    if profile is None:
        raise HTTPException(status_code=404, detail="no eligible events to compute embedding")
    with conn() as c, c.cursor() as cur:
        cur.execute(
            """
            INSERT INTO user_embeddings(uid, embedding, examples_count, updated_at)
            VALUES (%s, (%s)::float4[]::vector, %s, now())
            ON CONFLICT (uid) DO UPDATE
            SET embedding = EXCLUDED.embedding,
                examples_count = EXCLUDED.examples_count,
                updated_at = now()
            """,
            (uid, profile, len(vecs)),
        )
    print(f"[profile] force recompute done uid={uid} examples_count={len(vecs)}")
    return {"uid": uid, "examples_count": len(vecs)}

def fetch_user_liked_posts_content(uid: str, limit: int = 3) -> List[str]:
    """
    Fetch the body text of posts the user has liked or interacted with positively (weight >= 3.0).
    """
    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT p.body
            FROM user_events ue
            JOIN posts p ON p.id = ue.post_id
            WHERE ue.uid = %s AND ue.weight >= 3.0
            ORDER BY ue.ts DESC
            LIMIT %s
            """,
            (uid, limit),
        )
        rows = cur.fetchall()
    
    return [r["body"] for r in rows if r.get("body")]
