import logging
import requests

from app.core.config import settings
logger = logging.getLogger("peersync.email")

SENDGRID_API_URL = "https://api.sendgrid.com/v3/mail/send"


def send_professor_otp_email(
    recipient_email: str,
    otp_code: str
) -> None:
    """
    Send a Professor OTP verification email through SendGrid.
    """

    if not settings.sendgrid_api_key:
        raise RuntimeError("SendGrid API key is not configured.")

    if not settings.sendgrid_from_email:
        raise RuntimeError("SendGrid sender email is not configured.")

    payload = {
        "personalizations": [
            {
                "to": [
                    {"email": recipient_email}
                ],
                "subject": "PeerSync Professor Login Verification"
            }
        ],
        "from": {
            "email": settings.sendgrid_from_email,
            "name": "PeerSync"
        },
        "content": [
            {
                "type": "text/plain",
                "value": (
                    f"Your PeerSync Professor verification code is: {otp_code}\n\n"
                    f"This code expires in "
                    f"{settings.professor_otp_expire_minutes} minutes.\n\n"
                    "If you did not attempt to log in, please ignore this email."
                )
            }
        ]
    }

    headers = {
        "Authorization": f"Bearer {settings.sendgrid_api_key}",
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(
            SENDGRID_API_URL,
            headers=headers,
            json=payload,
            timeout=15
        )

        if response.status_code != 202:
            logger.error(
                "SendGrid email delivery request failed. HTTP status: %s",
                response.status_code
            )
            raise RuntimeError("Unable to send verification email.")

        logger.info("Professor OTP email accepted by SendGrid.")

    except requests.RequestException:
        logger.exception("SendGrid email request failed.")
        raise RuntimeError("Unable to send verification email.") from None