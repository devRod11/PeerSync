import logging

from fastapi import APIRouter, Depends, HTTPException, status
from firebase_admin import auth
from google.cloud.firestore import SERVER_TIMESTAMP
from pydantic import BaseModel, Field

from app.database.firebase import (
    get_firestore_client,
    initialize_firebase,
)
from app.dependencies.auth import require_professor

logger = logging.getLogger("peersync.users")

router = APIRouter(
    prefix="/users",
    tags=["User Management"],
)


class UserCreate(BaseModel):
    displayName: str = Field(min_length=2, max_length=100)
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)
    role: str = Field(pattern=r"^(student|professor)$")


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_user(
    request: UserCreate,
    current_user: dict = Depends(require_professor),
):
    """
    Create a Firebase Authentication account and its
    matching Firestore users/{uid} profile.

    Only an authenticated, OTP-verified Professor
    can register accounts.
    """

    initialize_firebase()

    db = get_firestore_client()

    email = request.email.strip().lower()
    display_name = request.displayName.strip()
    role = request.role.strip().lower()

    if not display_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Display name is required.",
        )

    # Create the Firebase Authentication account.
    try:
        firebase_user = auth.create_user(
            email=email,
            password=request.password,
            display_name=display_name,
            disabled=False,
        )

    except auth.EmailAlreadyExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        ) from None

    except Exception:
        logger.exception("Firebase Authentication account creation failed.")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create the account. Please try again.",
        ) from None

    uid = firebase_user.uid

    # Create the Firestore profile using the Firebase UID.
    profile_data = {
        "displayName": display_name,
        "email": email,
        "role": role,
        "isActive": True,
        "createdAt": SERVER_TIMESTAMP,
    }

    try:
        db.collection("users").document(uid).set(profile_data)

    except Exception:
        logger.exception(
            "Firestore profile creation failed for a new account."
        )

        # Roll back Authentication creation if Firestore fails.
        try:
            auth.delete_user(uid)
        except Exception:
            logger.exception(
                "Unable to roll back the newly created Firebase account."
            )

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to save the user profile. Please try again.",
        ) from None

    return {
        "message": "User account created successfully.",
        "user": {
            "uid": uid,
            "displayName": display_name,
            "email": email,
            "role": role,
            "isActive": True,
        },
    }