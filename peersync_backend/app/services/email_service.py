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
                "to": [{"email": recipient_email}],
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


def _format_digest_timestamp(value) -> str:
    """
    Convert a notification timestamp into readable text.
    Supports Firestore datetime values and strings.
    """

    if value is None:
        return "Date unavailable"

    if hasattr(value, "strftime"):
        return value.strftime("%Y-%m-%d %I:%M %p")

    return str(value)


def send_notification_digest_email(
    recipient_email: str,
    notifications: list[dict],
    period_started_at=None,
    period_ended_at=None
) -> None:
    """
    Send a summary of collected PeerSync notifications.

    This function is separate from Professor OTP delivery.
    It does not send individual notification emails.
    """

    if not settings.sendgrid_api_key:
        raise RuntimeError("SendGrid API key is not configured.")

    if not settings.sendgrid_from_email:
        raise RuntimeError("SendGrid sender email is not configured.")

    if not notifications:
        raise ValueError("Cannot send an empty notification digest.")

    notification_count = len(notifications)

    body_lines = [
        "Hello!",
        "",
        "Here is your PeerSync notification digest.",
        "",
        f"You received {notification_count} notification(s) during this period."
    ]

    if period_started_at is not None:
        body_lines.append(
            f"Period started: {_format_digest_timestamp(period_started_at)}"
        )

    if period_ended_at is not None:
        body_lines.append(
            f"Period ended: {_format_digest_timestamp(period_ended_at)}"
        )

    body_lines.extend([
        "",
        "YOUR NOTIFICATIONS",
        "------------------",
        ""
    ])

    # Prevent excessively long emails while reporting the full count.
    displayed_notifications = notifications[:50]

    for index, notification in enumerate(displayed_notifications, start=1):
        title = (
            notification.get("Title")
            or notification.get("title")
            or "PeerSync Notification"
        )

        description = (
            notification.get("description")
            or "No additional details provided."
        )

        created_at = _format_digest_timestamp(
            notification.get("createdAt")
        )

        body_lines.extend([
            f"{index}. {title}",
            f"   {description}",
            f"   Date: {created_at}",
            ""
        ])

    if notification_count > 50:
        body_lines.append(
            f"{notification_count - 50} additional notification(s) "
            "were omitted from this email."
        )

    body_lines.extend([
        "",
        "Log in to PeerSync to view your notifications and project updates.",
        "",
        "This is an automated notification digest."
        "",
        "Regards,",
        "PeerSync Team"
    ])

    payload = {
        "personalizations": [
            {
                "to": [{"email": recipient_email}],
                "subject": "PeerSync: Your 3-Day Notification Digest"
            }
        ],
        "from": {
            "email": settings.sendgrid_from_email,
            "name": "PeerSync"
        },
        "content": [
            {
                "type": "text/plain",
                "value": "\n".join(body_lines)
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
                "SendGrid digest email request failed. HTTP status: %s",
                response.status_code
            )
            raise RuntimeError("Unable to send notification digest.")

        logger.info(
            "Notification digest accepted by SendGrid for recipient: %s",
            recipient_email
        )

    except requests.RequestException:
        logger.exception("SendGrid digest email request failed.")
        raise RuntimeError("Unable to send notification digest.") from None