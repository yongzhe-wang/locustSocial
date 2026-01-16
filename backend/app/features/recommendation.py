import json
import random
from typing import Any, List, Dict
import psycopg2.extras
from ..db import conn

POPULARITY_ALPHA = 0.3

def get_recommendations(uid: str, limit: int = 15, cursor: int = 0) -> Dict[str, Any]:
    try:
        limit = min(max(limit, 1), 200)
        offset = int(cursor)
        print(f"[rank] computing recommendations for uid={uid} limit={limit} offset={offset}")

        # 1) Load user embedding
        with conn() as c, c.cursor() as cur:
            cur.execute("SELECT embedding FROM user_embeddings WHERE uid = %s", (uid,))
            row = cur.fetchone()
    except Exception as e:
        print(f"Error in get_recommendations step 1: {e}")
        raise e

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
