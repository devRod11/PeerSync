import hmac

from fastapi import APIRouter, Header, HTTPException, status

from app.core.config import settings
from app.database.firebase import get_firestore_client
from app.services.email_digest_service import (process_due_email_digests)

router = APIRouter(
    prefix="/internal/email-digests",
    tags=["Internal Email Digests"]
)


@router.post("/process")
def process_email_digests(
    cron_secret: str | None = Header(
        default=None,
        alias="X-Email-Digest-Secret"
    )
):
    """
    Protected endpoint for scheduled email digest processing.

    Only a caller with the configured cron secret can trigger it.
    """

    expected_secret = settings.email_digest_cron_secret

    if not expected_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Email digest scheduler is not configured."
        )

    if not cron_secret or not hmac.compare_digest(
        cron_secret,
        expected_secret
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid scheduler credentials."
        )

    try:
        db = get_firestore_client()

        results = process_due_email_digests(db)

        return {
            "message": "Email digest processing completed.",
            "results": results
        }

    except Exception:
        import logging

        logging.getLogger("peersync.email_digest").exception(
            "Email digest processing endpoint failed."
        )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Email digest processing failed."
        ) from None