import firebase_admin
from firebase_admin import credentials, firestore
from .settings import settings
import os

db = None

def init_firebase():
    global db
    if not firebase_admin._apps:
        # Default to emulator if not set
        if not os.environ.get("FIRESTORE_EMULATOR_HOST"):
            os.environ["FIRESTORE_EMULATOR_HOST"] = "127.0.0.1:8080"

        # Check for emulator environment variable
        if os.environ.get("FIRESTORE_EMULATOR_HOST"):
            print(f"🔧 Using Firestore Emulator at {os.environ.get('FIRESTORE_EMULATOR_HOST')}")
            # When using emulator, we can use a dummy project ID or the real one, 
            # but we don't strictly need the service account key if the env var is set correctly for the Admin SDK.
            # However, initialize_app still needs *some* credential or project ID.
            
            # Option 1: Use the service account but the env var redirects traffic.
            # Option 2: Use 'mock' credentials if we don't want to use the key file.
            
            cred_path = settings.FIREBASE_CREDENTIALS_PATH
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            else:
                # Fallback for emulator without key file (often works if project ID is set)
                print("⚠️ No credential file found, attempting to initialize for emulator with default project.")
                firebase_admin.initialize_app(options={'projectId': 'minutes-7c7d7'}) # Replace with your actual project ID if needed

            db = firestore.client()
            print("✅ Firebase initialized (Emulator Mode)")
            
        else:
            # Production / Non-emulator path
            cred_path = settings.FIREBASE_CREDENTIALS_PATH
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                db = firestore.client()
                print("✅ Firebase initialized successfully")
            else:
                print(f"⚠️ Firebase credentials not found at {cred_path}. AI Clone feature will be disabled.")
    else:
        db = firestore.client()

def get_firestore_db():
    if db is None:
        init_firebase()
    return db
