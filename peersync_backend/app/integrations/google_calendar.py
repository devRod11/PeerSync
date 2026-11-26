import logging
import requests
import json
import secrets
from datetime import datetime, timedelta, timezone

from cryptography.fernet import Fernet, InvalidToken
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from google_auth_oauthlib.flow import Flow

from app.core.config import settings
from app.database.firebase import get_firestore_client
logger = logging.getLogger(__name__)


# Students may create and manage events on calendars they own.
SCOPES = [
    "https://www.googleapis.com/auth/calendar.events.owned"
]

# Each student's credentials are stored in a separate document.
TOKEN_COLLECTION = "student_google_calendar_tokens"

# Temporary OAuth state documents.
STATE_COLLECTION = "google_calendar_oauth_states"

STATE_EXPIRATION_MINUTES = 10


class GoogleCalendarConfigurationError(Exception):
    pass


class GoogleCalendarOAuthError(Exception):
    pass


def _get_fernet():
    """Return the Fernet encryption instance."""

    key = settings.google_calendar_token_encryption_key

    if not key:
        raise GoogleCalendarConfigurationError(
            "Google Calendar token encryption key is not configured."
        )

    try:
        return Fernet(key.encode("utf-8"))
    except (ValueError, TypeError):
        raise GoogleCalendarConfigurationError(
            "Google Calendar token encryption key is invalid."
        ) from None


def _get_oauth_client_config():
    """Build the Google OAuth client configuration."""

    client_id = settings.google_calendar_client_id
    client_secret = settings.google_calendar_client_secret
    redirect_uri = settings.google_calendar_redirect_uri

    if not client_id or not client_secret or not redirect_uri:
        raise GoogleCalendarConfigurationError(
            "Google Calendar OAuth settings are incomplete."
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
    """Create a Google Calendar OAuth flow."""

    flow = Flow.from_client_config(
        _get_oauth_client_config(),
        scopes=SCOPES,
        state=state,
        code_verifier=code_verifier,
        autogenerate_code_verifier=autogenerate_code_verifier,
    )

    flow.redirect_uri = settings.google_calendar_redirect_uri

    return flow


def create_authorization_url(student_uid):
    """
    Generate an OAuth URL for one authenticated student.

    The Firebase UID and PKCE verifier are stored temporarily
    in Firestore and bound to the OAuth state.
    """

    db = get_firestore_client()

    state = secrets.token_urlsafe(32)

    flow = _create_flow(
        state=state,
        autogenerate_code_verifier=True,
    )

    authorization_url, _ = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",
    )

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(
        minutes=STATE_EXPIRATION_MINUTES
    )

    db.collection(STATE_COLLECTION).document(state).set({
        "state": state,
        "studentUID": student_uid,
        "codeVerifier": flow.code_verifier,
        "createdAt": now,
        "expiresAt": expires_at,
    })

    return authorization_url


def _consume_oauth_state(state):
    """
    Validate and consume a temporary OAuth state.

    Returns the Firebase UID and PKCE verifier associated
    with the authorization request.
    """

    if not state:
        raise GoogleCalendarOAuthError(
            "Missing OAuth state parameter."
        )

    db = get_firestore_client()

    state_ref = db.collection(STATE_COLLECTION).document(state)
    state_doc = state_ref.get()

    if not state_doc.exists:
        raise GoogleCalendarOAuthError(
            "Invalid or already-used OAuth state."
        )

    state_data = state_doc.to_dict()

    expires_at = state_data.get("expiresAt")
    student_uid = state_data.get("studentUID")
    code_verifier = state_data.get("codeVerifier")

    if not expires_at or not student_uid or not code_verifier:
        raise GoogleCalendarOAuthError(
            "OAuth state information is incomplete."
        )

    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)

    if datetime.now(timezone.utc) > expires_at:
        state_ref.delete()

        raise GoogleCalendarOAuthError(
            "OAuth state has expired. Please connect again."
        )

    # Consume the state to prevent reuse.
    state_ref.delete()

    return student_uid, code_verifier


def _save_encrypted_credentials(student_uid, credentials):
    """Encrypt and save one student's OAuth credentials."""

    db = get_firestore_client()
    fernet = _get_fernet()

    credentials_json = credentials.to_json()

    encrypted_credentials = fernet.encrypt(
        credentials_json.encode("utf-8")
    ).decode("utf-8")

    token_ref = (
        db.collection(TOKEN_COLLECTION)
        .document(student_uid)
    )

    existing = token_ref.get()
    now = datetime.now(timezone.utc)

    token_data = {
        "encryptedCredentials": encrypted_credentials,
        "provider": "google_calendar",
        "studentUID": student_uid,
        "updatedAt": now,
    }

    if not existing.exists:
        token_data["connectedAt"] = now

    token_ref.set(token_data, merge=True)


def exchange_authorization_code(code, state):
    """
    Exchange the Google authorization code and save the
    encrypted credentials for the student bound to the state.
    """

    if not code:
        raise GoogleCalendarOAuthError(
            "Missing Google authorization code."
        )

    student_uid, code_verifier = _consume_oauth_state(state)

    flow = _create_flow(
        state=state,
        code_verifier=code_verifier,
    )

    try:
        flow.fetch_token(code=code)

        credentials = flow.credentials

        if not credentials.refresh_token:
            raise GoogleCalendarOAuthError(
                "Google did not return a refresh token. "
                "Please reconnect and grant offline access."
            )

        _save_encrypted_credentials(
            student_uid,
            credentials,
        )

        return {
            "connected": True,
            "message": "Google Calendar connected successfully.",
        }

    except GoogleCalendarOAuthError:
        raise

    except Exception:
        raise GoogleCalendarOAuthError(
            "Google Calendar authorization failed. Please try again."
        ) from None


def get_google_calendar_credentials(student_uid):
    """
    Retrieve and decrypt a student's credentials.

    Automatically refreshes expired access tokens.
    """

    db = get_firestore_client()

    token_ref = (
        db.collection(TOKEN_COLLECTION)
        .document(student_uid)
    )

    token_doc = token_ref.get()

    if not token_doc.exists:
        raise GoogleCalendarOAuthError(
            "Google Calendar is not connected."
        )

    token_data = token_doc.to_dict()
    encrypted_credentials = token_data.get(
        "encryptedCredentials"
    )

    if not encrypted_credentials:
        raise GoogleCalendarOAuthError(
            "Stored Google Calendar credentials are missing."
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
        raise GoogleCalendarOAuthError(
            "Unable to decrypt or read Google Calendar credentials."
        ) from None

    if credentials.expired or not credentials.valid:

        if not credentials.refresh_token:
            raise GoogleCalendarOAuthError(
                "Google Calendar refresh token is unavailable. "
                "Please reconnect your account."
            )

        try:
            credentials.refresh(Request())

            _save_encrypted_credentials(
                student_uid,
                credentials,
            )

        except Exception:
            raise GoogleCalendarOAuthError(
                "Google Calendar token refresh failed. "
                "Please reconnect your account."
            ) from None

    return credentials


def get_google_calendar_service(student_uid):
    """Create an authenticated Calendar API client."""

    credentials = get_google_calendar_credentials(student_uid)

    return build(
        "calendar",
        "v3",
        credentials=credentials,
        cache_discovery=False,
    )


def get_google_calendar_status(student_uid):
    """Check whether a student has connected Google Calendar."""

    db = get_firestore_client()

    token_doc = (
        db.collection(TOKEN_COLLECTION)
        .document(student_uid)
        .get()
    )

    return {
        "connected": token_doc.exists,
        "provider": "google_calendar",
    }   

def disconnect_google_calendar(student_uid):
    """
    Revoke a student's Google authorization when possible,
    then remove the student's locally stored credentials.

    Local disconnection is completed even if Google's
    remote revocation request fails.
    """

    db = get_firestore_client()

    token_ref = (
        db.collection(TOKEN_COLLECTION)
        .document(student_uid)
    )

    token_doc = token_ref.get()

    if not token_doc.exists:
        return {
            "connected": False,
            "revocationConfirmed": False,
            "message": "Google Calendar is already disconnected.",
        }

    revocation_confirmed = False

    try:
        credentials = get_google_calendar_credentials(student_uid)

        # Prefer the refresh token to revoke the persistent
        # authorization granted to PeerSync.
        token_to_revoke = (
            credentials.refresh_token or credentials.token
        )

        if not token_to_revoke:
            raise GoogleCalendarOAuthError(
                "No Google token is available for revocation."
            )

        response = requests.post(
            "https://oauth2.googleapis.com/revoke",
            data={"token": token_to_revoke},
            headers={
                "Content-Type": "application/x-www-form-urlencoded"
            },
            timeout=15,
        )

        response.raise_for_status()
        revocation_confirmed = True

    except Exception as exc:
        # Do not prevent local disconnection if Google's
        # remote revocation request fails.
        logger.warning(
            "Google Calendar remote revocation failed "
            "for student %s (%s).",
            student_uid,
            type(exc).__name__,
        )

    # Always remove the student's locally stored credentials.
    # PeerSync can no longer use this connection afterward.
    token_ref.delete()

    if revocation_confirmed:
        return {
            "connected": False,
            "revocationConfirmed": True,
            "message": "Google Calendar disconnected successfully.",
        }

    return {
        "connected": False,
        "revocationConfirmed": False,
        "message": (
            "Disconnected from PeerSync, but Google could not "
            "confirm remote authorization revocation. You can "
            "also remove PeerSync from your Google Account's "
            "third-party connections."
        ),
    }