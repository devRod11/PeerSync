import hashlib
import hmac
import logging
import secrets

from datetime import datetime, timedelta, timezone
from google.cloud import firestore
from app.core.config import settings
from app.database.firebase import get_firestore_client
from app.services.email_service import send_professor_otp_email
logger = logging.getLogger("peersync.professor_otp")

OTP_COLLECTION = "professor_otp_challenges"
OTP_LENGTH = 6
OTP_RESEND_COOLDOWN_SECONDS = 60


def _get_otp_hash(uid: str, code: str) -> str:
    secret = settings.professor_otp_hash_secret

    if not secret:
        raise RuntimeError(
            "Professor OTP hash secret is not configured."
        )

    message = f"{uid}:{code}".encode("utf-8")

    return hmac.new(
        secret.encode("utf-8"),
        message,
        hashlib.sha256
    ).hexdigest()


def issue_professor_otp(uid: str, email: str) -> dict:
    """
    Generate and email a six-digit OTP to a Professor.

    Only the protected OTP hash is stored in Firestore.
    """

    db = get_firestore_client()

    challenge_ref = (
        db.collection(OTP_COLLECTION)
        .document(uid)
    )

    now = datetime.now(timezone.utc)

    # Check the resend cooldown.
    existing = challenge_ref.get()

    if existing.exists:
        existing_data = existing.to_dict() or {}
        created_at = existing_data.get("createdAt")

        if created_at:
            elapsed = (
                now - created_at
            ).total_seconds()

            if elapsed < OTP_RESEND_COOLDOWN_SECONDS:
                raise ValueError(
                    "Please wait before requesting another verification code."
                )

    code = f"{secrets.randbelow(1_000_000):06d}"

    challenge_ref.set({
        "otpHash": _get_otp_hash(uid, code),
        "createdAt": now,
        "expiresAt": now + timedelta(
            minutes=settings.professor_otp_expire_minutes
        ),
        "attempts": 0,
    })

    try:
        send_professor_otp_email(email, code)

    except Exception:
        challenge_ref.delete()

        logger.exception(
            "Unable to send Professor OTP email."
        )

        raise RuntimeError(
            "Unable to send verification email. Please try again."
        ) from None

    return {
        "message": "Verification code sent to your registered email.",
        "expiresInMinutes": settings.professor_otp_expire_minutes,
    }


def verify_professor_otp(
    uid: str,
    submitted_code: str
) -> bool:
    """
    Verify a Professor OTP using a Firestore transaction.

    Enforces expiration and attempt limits atomically.
    Successfully verified OTPs are consumed and cannot be reused.
    """

    if (
        not isinstance(submitted_code, str)
        or len(submitted_code) != OTP_LENGTH
        or not submitted_code.isdigit()
    ):
        return False

    db = get_firestore_client()

    challenge_ref = (
        db.collection(OTP_COLLECTION)
        .document(uid)
    )

    transaction = db.transaction()

    @firestore.transactional
    def verify_transaction(transaction):
        challenge = challenge_ref.get(
            transaction=transaction
        )

        if not challenge.exists:
            return False

        data = challenge.to_dict() or {}

        now = datetime.now(timezone.utc)

        expires_at = data.get("expiresAt")
        attempts = data.get("attempts", 0)
        expected_hash = data.get("otpHash")

        if (
            not expires_at
            or now >= expires_at
            or not isinstance(expected_hash, str)
        ):
            transaction.delete(challenge_ref)
            return False

        try:
            attempts = int(attempts)
        except (TypeError, ValueError):
            transaction.delete(challenge_ref)
            return False

        if attempts >= settings.professor_otp_max_attempts:
            transaction.delete(challenge_ref)
            return False

        submitted_hash = _get_otp_hash(
            uid,
            submitted_code
        )

        if not hmac.compare_digest(
            expected_hash,
            submitted_hash
        ):
            next_attempt = attempts + 1

            if next_attempt >= settings.professor_otp_max_attempts:
                transaction.delete(challenge_ref)
            else:
                transaction.update(
                    challenge_ref,
                    {"attempts": next_attempt}
                )

            return False

        # Consume the OTP after successful verification.
        transaction.delete(challenge_ref)

        return True

    return verify_transaction(transaction)