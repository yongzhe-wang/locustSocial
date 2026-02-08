import os

class Settings:
    PG_DSN: str = os.environ.get("PG_DSN", "postgres://app:secret@postgres:5432/app")
    CORS_ALLOW_ORIGINS: str = os.environ.get("CORS_ALLOW_ORIGINS", "*")

    # Cohere embed defaults
    COHERE_API_KEY: str = os.environ.get("COHERE_API_KEY", "")
    COHERE_EMBED_MODEL: str = os.environ.get("COHERE_EMBED_MODEL", "embed-v4.0")
    COHERE_EMBED_DIM: int = int(os.environ.get("COHERE_EMBED_DIM", "1536"))
    COHERE_TIMEOUT: float = float(os.environ.get("COHERE_TIMEOUT", "30"))

    # Upload limits
    MAX_IMAGE_BYTES: int = int(os.environ.get("MAX_IMAGE_BYTES", str(10 * 1024 * 1024)))

settings = Settings()
