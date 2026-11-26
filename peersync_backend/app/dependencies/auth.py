import logging

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth
from app.database.firebase import get_firestore_client, initialize_firebase
from app.services.professor_session_service import (validate_professor_session,)
logger = logging.getLogger("peersync.auth")
bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme)
):
    """
    Verify Firebase authentication and retrieve the user's Firestore profile.
    """

    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials are required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        initialize_firebase()

        decoded_token = auth.verify_id_token(
            credentials.credentials,
            check_revoked=True
        )

        uid = decoded_token.get("uid")

        if not uid:
            raise ValueError("Missing Firebase UID.")

    except Exception:
        logger.warning(
            "Firebase ID token verification failed.",
            exc_info=True
        )

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None

    try:
        db = get_firestore_client()

        user_document = (
            db.collection("users")
            .document(uid)
            .get()
        )

    except Exception:
        logger.exception("Firestore user lookup failed.")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to verify user profile."
        ) from None

    if not user_document.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User profile does not exist."
        )

    user_data = user_document.to_dict() or {}

    if user_data.get("isActive") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is inactive."
        )

    role = str(user_data.get("role", "")).strip().lower()

    if role not in ["professor", "student"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User role is not authorized."
        )

    return {
        "uid": uid,
        "displayName": user_data.get("displayName"),
        "email": user_data.get("email"),
        "role": role,
        "isActive": True
    }


def require_professor_identity(
    current_user: dict = Depends(get_current_user)
):
    """
    Verify Professor identity without requiring OTP verification.

    Use only for the Professor OTP request and verification endpoints.
    """

    if current_user["role"] != "professor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Professor access required."
        )

    return current_user


def require_professor(
    current_user: dict = Depends(require_professor_identity),
    professor_session: str | None = Header(
        default=None,
        alias="X-Professor-OTP-Session"
    )
):
    """
    Require both Firebase Professor authentication
    and a valid OTP-verified Professor session.
    """

    try:
        session_valid = validate_professor_session(
            uid=current_user["uid"],
            session_token=professor_session
        )

    except Exception:
        logger.exception("Professor session validation failed.")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to verify Professor session."
        ) from None

    if not session_valid:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Professor OTP verification is required."
        )

    return current_user


def require_student(
    current_user: dict = Depends(get_current_user)
):
    """
    Allow access only to authenticated Students.
    """

    if current_user["role"] != "student":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Student access required."
        )

    return current_user