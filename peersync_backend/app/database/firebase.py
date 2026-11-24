from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

from app.core.config import BACKEND_ROOT, settings

_firebase_app = None
_firestore_client = None


def initialize_firebase():
    """
    Initialize Firebase Admin SDK and Firestore.
    Reuses the existing Firebase app if already initialized.
    """
    global _firebase_app, _firestore_client

    if _firebase_app is not None and _firestore_client is not None:
        return _firebase_app

    try:
        # Reuse an existing default Firebase app.
        _firebase_app = firebase_admin.get_app()

    except ValueError:
        credential_path = Path(settings.firebase_credentials_path)

        # Resolve relative paths from the backend root.
        if not credential_path.is_absolute():
            credential_path = BACKEND_ROOT / credential_path

        if not credential_path.exists():
            raise FileNotFoundError(
                f"Firebase service account file not found: "
                f"{credential_path}"
            ) from None

        firebase_credential = credentials.Certificate(
            str(credential_path)
        )

        _firebase_app = firebase_admin.initialize_app(
            firebase_credential,
            {
                "projectId": settings.firebase_project_id
            }
        )

    # Initialize Firestore using the Firebase app.
    _firestore_client = firestore.client(_firebase_app)

    return _firebase_app


def get_firestore_client():
    """
    Return the initialized Firestore client.
    Initializes Firebase automatically if necessary.
    """
    if _firestore_client is None:
        initialize_firebase()

    return _firestore_client
