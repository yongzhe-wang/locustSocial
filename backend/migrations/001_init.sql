-- db/init/001_posts.sql
CREATE EXTENSION IF NOT EXISTS vector;

DROP TABLE IF EXISTS posts CASCADE;

CREATE TABLE posts (
  id               SERIAL PRIMARY KEY,
  title            TEXT NOT NULL,
  body             TEXT,
  embedding        vector(1536),
  embedding_model  TEXT DEFAULT 'embed-v4.0',
  embedding_version INT  DEFAULT 1,
  created_at       TIMESTAMPTZ DEFAULT now(),
  firebase_id      TEXT UNIQUE
);

-- ANN index for cosine distance on embeddings
CREATE INDEX IF NOT EXISTS posts_embedding_idx
  ON posts USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Optional: also index firebase_id (the UNIQUE already builds one)
-- CREATE UNIQUE INDEX IF NOT EXISTS posts_firebase_id_uq ON posts(firebase_id);
