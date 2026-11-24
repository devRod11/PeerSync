import logging

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from app.database.firebase import get_firestore_client, initialize_firebase

logger = logging.getLogger("peersync.auth")


# Extract the Bearer token from the Authorization header.
bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme)
):
    """
    Verify the Firebase ID token and retrieve the
    authenticated user's Firestore profile.
    """

    # 1. Check whether an Authorization header exists.
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials are required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 2. Verify the Firebase ID token.
    try:
        initialize_firebase()

        decoded_token = auth.verify_id_token(
            credentials.credentials,
            check_revoked=True
        )

        uid = decoded_token.get("uid")

        if not uid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication token."
            )

    except Exception:
        # Log the failure for operators without exposing token details to
        # the client or to stdout.
        logger.warning("Firebase ID token verification failed.", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None

    # 3. Retrieve the user's profile from Firestore.
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

    # 4. Check whether the user profile exists.
    if not user_document.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User profile does not exist."
        )

    user_data = user_document.to_dict() or {}

    # 5. Check account activity.
    if user_data.get("isActive") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is inactive."
        )

    # 6. Validate the user's application role.
    role = str(user_data.get("role", "")).strip().lower()

    if role not in ["professor", "student"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User role is not authorized."
        )

    # 7. Return authenticated user information.
    return {
        "uid": uid,
        "displayName": user_data.get("displayName"),
        "email": user_data.get("email"),
        "role": role,
        "isActive": True
    }


def require_professor(
    current_user: dict = Depends(get_current_user)
):
    """
    Allow access only to authenticated Professors.
    """

    if current_user["role"] != "professor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Professor access required."
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