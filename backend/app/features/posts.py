from app.db import conn
from app.embeddings import cohere_embed
from app.settings import settings
import psycopg2.extras
import time
import base64

def _compute_and_save_embedding(
    post_id: int,
    firebase_id: str | None,
    text: str,
    img_bytes_list: list[bytes] | None,
):
    print(f"[embed] start post_id={post_id}")

    with conn() as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT
              COALESCE(title, '') AS title,
              COALESCE(body,  '') AS body
            FROM posts
            WHERE id = %s
            """,
            (post_id,),
        )
        row = cur.fetchone()

    full_text = (row["title"] + " " + row["body"]).strip()
    print(f"[embed] text_preview='{full_text[:80]}' images={len(img_bytes_list) if img_bytes_list else 0}")

    e = cohere_embed(
        full_text,
        img_bytes_list,
        input_type="search_document",
        output_dimension=settings.COHERE_EMBED_DIM,
    )
    print(f"[embed] embedding_len={len(e)}")

    with conn() as c, c.cursor() as cur:
        cur.execute(
            """
            UPDATE posts
            SET
              embedding         = (%s)::float4[]::vector,
              embedding_model   = %s,
              embedding_version = %s
            WHERE id = %s
            """,
            (e, settings.COHERE_EMBED_MODEL, 1, post_id),
        )

    print(f"[embed] saved post_id={post_id}")
