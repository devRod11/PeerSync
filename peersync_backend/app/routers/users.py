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

class UserStatusUpdate(BaseModel):
    isActive: bool

@router.get("/")
def get_users(
    current_user: dict = Depends(require_professor),
):
    """
    Retrieve all registered user profiles.

    Only an authenticated, OTP-verified Professor
    can view the user list.
    """

    initialize_firebase()

    try:
        db = get_firestore_client()

        user_documents = db.collection("users").stream()

        users = []

        for document in user_documents:
            data = document.to_dict() or {}

            created_at = data.get("createdAt")

            # Convert Firestore timestamps into JSON-friendly strings.
            if hasattr(created_at, "isoformat"):
                created_at = created_at.isoformat()

            users.append({
                "uid": document.id,
                "displayName": data.get("displayName", ""),
                "email": data.get("email", ""),
                "role": data.get("role", ""),
                "isActive": data.get("isActive") is True,
                "createdAt": created_at,
            })

        # Keep the list organized alphabetically by display name.
        users.sort(
            key=lambda user: user["displayName"].casefold()
        )

        return {
            "count": len(users),
            "users": users,
        }

    except Exception:
        logger.exception("Unable to retrieve user accounts.")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to retrieve user accounts. Please try again.",
        ) from None

@router.patch("/{uid}/status")
def update_user_status(
    uid: str,
    request: UserStatusUpdate,
    current_user: dict = Depends(require_professor),
):
    """
    Activate or deactivate a user account.

    Updates both Firebase Authentication and Firestore.
    Only an authenticated, OTP-verified Professor can
    change account status.
    """

    initialize_firebase()

    # Prevent a Professor from deactivating their own account.
    if uid == current_user["uid"] and request.isActive is False:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot deactivate your own account.",
        )

    try:
        db = get_firestore_client()
        user_ref = db.collection("users").document(uid)
        user_document = user_ref.get()

        if not user_document.exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User account not found.",
            )

        user_data = user_document.to_dict() or {}

        # Confirm the target account has a valid role.
        role = str(user_data.get("role", "")).strip().lower()

        if role not in ["student", "professor"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid user account role.",
            )

        # Retrieve the Firebase Authentication account.
        firebase_user = auth.get_user(uid)

        previous_firestore_status = user_data.get("isActive") is True
        previous_auth_status = not firebase_user.disabled

        try:
            # Update Firebase Authentication first.
            auth.update_user(
                uid,
                disabled=not request.isActive,
            )

            # Keep the Firestore profile synchronized.
            user_ref.update({
                "isActive": request.isActive,
            })

        except Exception:
            logger.exception(
                "Account status update failed for UID %s.",
                uid,
            )

            # Attempt to restore the previous Firebase status.
            try:
                auth.update_user(
                    uid,
                    disabled=not previous_auth_status,
                )
            except Exception:
                logger.exception(
                    "Unable to restore Firebase account status for UID %s.",
                    uid,
                )

            # Attempt to restore the previous Firestore status.
            try:
                user_ref.update({
                    "isActive": previous_firestore_status,
                })
            except Exception:
                logger.exception(
                    "Unable to restore Firestore account status for UID %s.",
                    uid,
                )

            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Unable to update account status. Please try again.",
            ) from None

        return {
            "message": (
                "Account activated successfully."
                if request.isActive
                else "Account deactivated successfully."
            ),
            "user": {
                "uid": uid,
                "displayName": user_data.get("displayName", ""),
                "email": user_data.get("email", ""),
                "role": role,
                "isActive": request.isActive,
            },
        }

    except HTTPException:
        raise

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Firebase Authentication account not found.",
        ) from None

    except Exception:
        logger.exception(
            "Unable to update account status for UID %s.",
            uid,
        )

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to update account status. Please try again.",
        ) from None

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