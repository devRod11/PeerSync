from fastapi import APIRouter, Depends, HTTPException, Query
from app.dependencies.auth import require_professor
from app.integrations.google_drive import (
    GoogleDriveConfigurationError,
    GoogleDriveOAuthError,
    create_authorization_url,
    exchange_authorization_code,
    get_google_drive_status,
)

router = APIRouter(
    prefix="/google-drive",
    tags=["Google Drive"],
)


@router.get("/oauth/authorize")
def authorize_google_drive(
    current_user: dict = Depends(require_professor),
):
    """
    Starts the Google Drive OAuth authorization process.
    Professor access is required.
    """
    try:
        authorization_url = create_authorization_url()

        return {
            "message": "Google Drive authorization URL generated.",
            "authorizationUrl": authorization_url,
        }

    except GoogleDriveConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleDriveOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None


@router.get("/oauth/callback")
def google_drive_oauth_callback(
    code: str | None = Query(default=None),
    state: str | None = Query(default=None),
    error: str | None = Query(default=None),
):
    """
    Handles Google's redirect after the user authorizes PeerSync.
    This endpoint does not require Firebase authentication because
    Google redirects the browser here.
    """

    if error:
        raise HTTPException(
            status_code=400,
            detail="Google Drive authorization was denied or cancelled.",
        )

    if not code or not state:
        raise HTTPException(
            status_code=400,
            detail="Missing authorization code or state.",
        )

    try:
        result = exchange_authorization_code(
            code=code,
            state=state,
        )

        return result

    except GoogleDriveConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleDriveOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None


@router.get("/status")
def google_drive_connection_status(
    current_user: dict = Depends(require_professor),
):
    """
    Checks whether the designated Google Drive account is connected.
    Professor access is required.
    """
    try:
        return get_google_drive_status()

    except GoogleDriveConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleDriveOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None
