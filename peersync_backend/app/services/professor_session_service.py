import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from app.database.firebase import get_firestore_client

SESSION_COLLECTION = "professor_otp_sessions"
SESSION_EXPIRE_HOURS = 8


def _hash_session_token(token: str) -> str:
    return hashlib.sha256(
        token.encode("utf-8")
    ).hexdigest()


def create_professor_session(uid: str) -> dict:
    """
    Create an expiring Professor session after successful OTP verification.

    The raw session token is returned once to Flutter.
    Only its SHA-256 hash is stored in Firestore.
    """

    db = get_firestore_client()

    session_token = secrets.token_urlsafe(32)
    token_hash = _hash_session_token(session_token)

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(hours=SESSION_EXPIRE_HOURS)

    db.collection(SESSION_COLLECTION).document(
        token_hash
    ).set({
        "uid": uid,
        "createdAt": now,
        "expiresAt": expires_at,
        "revoked": False,
    })

    return {
        "sessionToken": session_token,
        "expiresAt": expires_at.isoformat(),
        "expiresInHours": SESSION_EXPIRE_HOURS,
    }


def validate_professor_session(
    uid: str,
    session_token: str | None
) -> bool:
    """
    Validate that a Professor session exists, belongs to the
    authenticated Firebase user, and has not expired or been revoked.
    """

    if not session_token:
        return False

    db = get_firestore_client()

    token_hash = _hash_session_token(session_token)

    session_ref = (
        db.collection(SESSION_COLLECTION)
        .document(token_hash)
    )

    session = session_ref.get()

    if not session.exists:
        return False

    data = session.to_dict() or {}

    expires_at = data.get("expiresAt")

    if (
        data.get("uid") != uid
        or data.get("revoked") is True
        or not expires_at
        or datetime.now(timezone.utc) >= expires_at
    ):
        return False

    return True


def revoke_professor_session(
    uid: str,
    session_token: str | None
) -> bool:
    """
    Revoke the supplied Professor session.
    """

    if not session_token:
        return False

    db = get_firestore_client()

    token_hash = _hash_session_token(session_token)

    session_ref = (
        db.collection(SESSION_COLLECTION)
        .document(token_hash)
    )

    session = session_ref.get()

    if not session.exists:
        return False

    data = session.to_dict() or {}

    if data.get("uid") != uid:
        return False

    session_ref.delete()

    return True