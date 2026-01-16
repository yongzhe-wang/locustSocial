import os
from dotenv import load_dotenv

load_dotenv()

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

    # AI Clone
    # Try to find the credentials file
    _default_cred_path = "minutes-7c7d7-firebase-adminsdk-fbsvc-1b75b1d2e2.json"
    if not os.path.exists(_default_cred_path):
        # Try looking in backend/ if running from project root
        if os.path.exists(f"backend/{_default_cred_path}"):
            _default_cred_path = f"backend/{_default_cred_path}"
        # Try absolute path from previous default as fallback
        elif os.path.exists("/Users/thebigsun/Desktop/projects/social_media_project/social_media_project/backend/minutes-7c7d7-firebase-adminsdk-fbsvc-1b75b1d2e2.json"):
            _default_cred_path = "/Users/thebigsun/Desktop/projects/social_media_project/social_media_project/backend/minutes-7c7d7-firebase-adminsdk-fbsvc-1b75b1d2e2.json"

    FIREBASE_CREDENTIALS_PATH: str = os.environ.get("FIREBASE_CREDENTIALS_PATH", _default_cred_path)
    GEMINI_API_KEY: str = os.environ.get("GEMINI_API_KEY", "AIzaSyA7GdMi87cJ6qgxnnf2QiF4bxBSCTrDKLc")

settings = Settings()
