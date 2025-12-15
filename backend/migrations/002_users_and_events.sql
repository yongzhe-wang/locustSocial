-- 001b_users_and_events.sql
CREATE TABLE users (
  uid            TEXT PRIMARY KEY,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  -- user-level features (country, lang, device, etc. – optional)
  meta           JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE user_events (
  id             BIGSERIAL PRIMARY KEY,
  uid            TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  post_id        INT  NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  etype          TEXT NOT NULL,   -- 'view', 'like', 'comment', 'save', 'share'
  weight         REAL NOT NULL,   -- default per event type (see §4)
  ts             TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX user_events_uid_ts_idx ON user_events (uid, ts DESC);
CREATE INDEX user_events_post_idx   ON user_events (post_id);

-- One embedding per user (rolling, from last N events)
CREATE TABLE user_embeddings (
  uid               TEXT PRIMARY KEY REFERENCES users(uid) ON DELETE CASCADE,
  embedding         vector(1536),
  embedding_model   TEXT DEFAULT 'embed-v4.0',
  embedding_version INT  DEFAULT 1,
  examples_count    INT  DEFAULT 0,  -- number of events used
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Fast fetch of fresh & eligible posts (optional but helpful)
CREATE MATERIALIZED VIEW mv_recent_posts AS
SELECT id, title, body, created_at, embedding
FROM posts
WHERE embedding IS NOT NULL
ORDER BY created_at DESC
LIMIT 5000;

CREATE INDEX mv_recent_posts_embed_idx
  ON mv_recent_posts USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
