import json
import secrets
from datetime import datetime, timedelta, timezone

from cryptography.fernet import Fernet, InvalidToken
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload
from googleapiclient.errors import HttpError
from google_auth_oauthlib.flow import Flow

from app.core.config import settings
from app.database.firebase import get_firestore_client


# Google Drive permission required by PeerSync.
SCOPES = [
    "https://www.googleapis.com/auth/drive.file"
]

# Private Firestore document for encrypted OAuth credentials.
TOKEN_COLLECTION = "system_integrations"
TOKEN_DOCUMENT = "google_drive"

# Temporary OAuth state documents.
STATE_COLLECTION = "google_drive_oauth_states"

STATE_EXPIRATION_MINUTES = 10


class GoogleDriveConfigurationError(Exception):
    pass


class GoogleDriveOAuthError(Exception):
    pass


def _get_fernet():
    """Return the Fernet encryption instance."""

    key = settings.google_drive_token_encryption_key

    if not key:
        raise GoogleDriveConfigurationError(
            "Google Drive token encryption key is not configured."
        )

    try:
        return Fernet(key.encode("utf-8"))
    except (ValueError, TypeError):
        raise GoogleDriveConfigurationError(
            "Google Drive token encryption key is invalid."
        ) from None


def _get_oauth_client_config():
    """Build the OAuth client configuration."""

    client_id = settings.google_drive_client_id
    client_secret = settings.google_drive_client_secret
    redirect_uri = settings.google_drive_redirect_uri

    if not client_id or not client_secret or not redirect_uri:
        raise GoogleDriveConfigurationError(
            "Google Drive OAuth settings are incomplete."
        )

    return {
        "web": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [redirect_uri],
        }
    }


def _create_flow(
    state=None,
    code_verifier=None,
    autogenerate_code_verifier=False,
):
    """Create a Google OAuth flow."""

    flow = Flow.from_client_config(
        _get_oauth_client_config(),
        scopes=SCOPES,
        state=state,
        code_verifier=code_verifier,
        autogenerate_code_verifier=autogenerate_code_verifier,
    )

    flow.redirect_uri = settings.google_drive_redirect_uri

    return flow


def create_authorization_url():
    """
    Generate a Google OAuth authorization URL.

    Stores temporary OAuth state and PKCE verifier in Firestore.
    """

    db = get_firestore_client()

    state = secrets.token_urlsafe(32)

    flow = _create_flow(
        state=state,
        autogenerate_code_verifier=True,
    )

    authorization_url, returned_state = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",
    )

    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=STATE_EXPIRATION_MINUTES
    )

    db.collection(STATE_COLLECTION).document(state).set({
        "state": state,
        "codeVerifier": flow.code_verifier,
        "createdAt": datetime.now(timezone.utc),
        "expiresAt": expires_at,
    })

    return authorization_url


def _consume_oauth_state(state):
    """
    Validate and consume a temporary OAuth state.

    Returns the associated PKCE code verifier.
    """

    if not state:
        raise GoogleDriveOAuthError(
            "Missing OAuth state parameter."
        )

    db = get_firestore_client()

    state_ref = db.collection(STATE_COLLECTION).document(state)
    state_doc = state_ref.get()

    if not state_doc.exists:
        raise GoogleDriveOAuthError(
            "Invalid or already-used OAuth state."
        )

    state_data = state_doc.to_dict()

    expires_at = state_data.get("expiresAt")

    if not expires_at:
        raise GoogleDriveOAuthError(
            "OAuth state expiration is missing."
        )

    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)

    if datetime.now(timezone.utc) > expires_at:
        state_ref.delete()

        raise GoogleDriveOAuthError(
            "OAuth state has expired. Please authorize again."
        )

    code_verifier = state_data.get("codeVerifier")

    if not code_verifier:
        raise GoogleDriveOAuthError(
            "PKCE code verifier is missing. Please authorize again."
        )

    # Consume the state after successful validation.
    state_ref.delete()

    return code_verifier


def _save_encrypted_credentials(credentials, is_initial=False):
    """
    Encrypt and store Google OAuth credentials in Firestore.

    The refresh token is never stored in plaintext.
    """

    db = get_firestore_client()
    fernet = _get_fernet()

    credentials_json = credentials.to_json()

    encrypted_credentials = fernet.encrypt(
        credentials_json.encode("utf-8")
    ).decode("utf-8")

    token_ref = db.collection(TOKEN_COLLECTION).document(
        TOKEN_DOCUMENT
    )

    existing = token_ref.get()

    token_data = {
        "encryptedCredentials": encrypted_credentials,
        "updatedAt": datetime.now(timezone.utc),
        "provider": "google_drive",
    }

    if is_initial or not existing.exists:
        token_data["connectedAt"] = datetime.now(timezone.utc)

    token_ref.set(token_data, merge=True)


def exchange_authorization_code(code, state):
    """
    Exchange the Google authorization code for OAuth credentials.

    Restores the PKCE verifier and securely stores the credentials.
    """

    if not code:
        raise GoogleDriveOAuthError(
            "Missing Google authorization code."
        )

    code_verifier = _consume_oauth_state(state)

    flow = _create_flow(
        state=state,
        code_verifier=code_verifier,
    )

    try:
        flow.fetch_token(code=code)

        credentials = flow.credentials

        if not credentials.refresh_token:
            raise GoogleDriveOAuthError(
                "Google did not return a refresh token. "
                "Please authorize again and grant offline access."
            )

        _save_encrypted_credentials(
            credentials,
            is_initial=True,
        )

        return {
            "connected": True,
            "message": "Google Drive authorization completed.",
        }

    except GoogleDriveOAuthError:
        raise

    except Exception as exc:
        raise GoogleDriveOAuthError(
            f"Google OAuth authorization failed: {str(exc)}"
        ) from None


def get_google_drive_credentials():
    """
    Retrieve and decrypt stored credentials.

    Automatically refreshes expired access tokens.
    """

    db = get_firestore_client()

    token_ref = db.collection(TOKEN_COLLECTION).document(
        TOKEN_DOCUMENT
    )

    token_doc = token_ref.get()

    if not token_doc.exists:
        raise GoogleDriveOAuthError(
            "Google Drive is not connected. "
            "Complete OAuth authorization first."
        )

    token_data = token_doc.to_dict()
    encrypted_credentials = token_data.get(
        "encryptedCredentials"
    )

    if not encrypted_credentials:
        raise GoogleDriveOAuthError(
            "Stored Google Drive credentials are missing."
        )

    try:
        fernet = _get_fernet()

        decrypted_credentials = fernet.decrypt(
            encrypted_credentials.encode("utf-8")
        ).decode("utf-8")

        credentials_info = json.loads(decrypted_credentials)

        credentials = Credentials.from_authorized_user_info(
            credentials_info,
            scopes=SCOPES,
        )

    except (InvalidToken, ValueError, KeyError, TypeError):
        raise GoogleDriveOAuthError(
            "Unable to decrypt or read Google Drive credentials. "
            "Check the configured encryption key."
        ) from None

    if credentials.expired or not credentials.valid:

        if not credentials.refresh_token:
            raise GoogleDriveOAuthError(
                "Google Drive refresh token is unavailable. "
                "Reconnect Google Drive."
            )

        try:
            credentials.refresh(Request())

            # Persist the refreshed access token securely.
            _save_encrypted_credentials(credentials)

        except Exception:
            raise GoogleDriveOAuthError(
                "Google Drive token refresh failed. "
                "Reconnect Google Drive."
            ) from None

    return credentials


def get_google_drive_service():
    """Create an authenticated Google Drive API client."""

    credentials = get_google_drive_credentials()

    return build(
        "drive",
        "v3",
        credentials=credentials,
        cache_discovery=False,
    )


def get_google_drive_status():
    """Return whether Google Drive has stored OAuth credentials."""

    db = get_firestore_client()

    token_doc = db.collection(TOKEN_COLLECTION).document(
        TOKEN_DOCUMENT
    ).get()

    return {
        "connected": token_doc.exists,
        "provider": "google_drive",
    }

def upload_drive_file(file_stream, file_name, mime_type):
    """Upload a file to the designated Google Drive account."""

    try:
        service = get_google_drive_service()

        file_metadata = {
            "name": file_name,
        }

        # Use the configured folder when available.
        if settings.google_drive_folder_id:
            file_metadata["parents"] = [
                settings.google_drive_folder_id
            ]

        media = MediaIoBaseUpload(
            file_stream,
            mimetype=mime_type,
            resumable=True,
        )

        uploaded_file = (
            service.files()
            .create(
                body=file_metadata,
                media_body=media,
                fields="id,name,mimeType,size",
            )
            .execute()
        )

        return {
            "driveFileId": uploaded_file["id"],
            "fileName": uploaded_file["name"],
            "mimeType": uploaded_file.get("mimeType"),
            "size": uploaded_file.get("size"),
        }

    except Exception:
        raise GoogleDriveOAuthError(
            "Unable to upload the file to Google Drive."
        ) from None


def download_drive_file(file_id):
    """Download a private Google Drive file."""

    try:
        service = get_google_drive_service()

        metadata = (
            service.files()
            .get(
                fileId=file_id,
                fields="name,mimeType",
            )
            .execute()
        )

        content = (
            service.files()
            .get_media(fileId=file_id)
            .execute()
        )

        return {
            "fileName": metadata["name"],
            "mimeType": metadata.get(
                "mimeType",
                "application/octet-stream",
            ),
            "content": content,
        }

    except Exception:
        raise GoogleDriveOAuthError(
            "Unable to retrieve the Google Drive file."
        ) from None


def delete_drive_file(file_id):
    """Permanently delete a file from Google Drive.

    Treat an already-missing file as successfully deleted.
    This makes cleanup safe to retry.
    """

    try:
        service = get_google_drive_service()

        service.files().delete(
            fileId=file_id,
        ).execute()

        return True

    except HttpError as exc:
        # Google Drive returns 404 if the file is already missing.
        if exc.resp.status == 404:
            return True

        raise GoogleDriveOAuthError(
            "Unable to delete the Google Drive file."
        ) from None

    except Exception:
        raise GoogleDriveOAuthError(
            "Unable to delete the Google Drive file."
        ) from None