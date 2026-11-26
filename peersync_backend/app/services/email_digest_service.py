import logging
from datetime import datetime, timedelta, timezone

from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.services.email_service import send_notification_digest_email
logger = logging.getLogger("peersync.email_digest")

DIGEST_COLLECTION = "email_digests"
NOTIFICATION_COLLECTION = "notifications"
USER_COLLECTION = "users"

DIGEST_INTERVAL_HOURS = 72
DIGEST_LEASE_MINUTES = 10


def _claim_digest(db, digest_ref, now):
    """
    Atomically claim a due digest.

    A digest already being processed by another worker is skipped.
    Expired processing leases can be reclaimed after a worker failure.
    """

    transaction = db.transaction()

    @firestore.transactional
    def claim(transaction):
        snapshot = digest_ref.get(transaction=transaction)

        if not snapshot.exists:
            return None

        data = snapshot.to_dict() or {}

        next_digest_at = data.get("nextDigestAt")
        status = data.get("status")

        if not next_digest_at or next_digest_at > now:
            return None

        if status == "sending":
            lease_until = data.get("leaseUntil")

            if lease_until and lease_until > now:
                return None

        elif status != "collecting":
            return None

        transaction.update(
            digest_ref,
            {
                "status": "sending",
                "leaseUntil": now + timedelta(
                    minutes=DIGEST_LEASE_MINUTES
                ),
                "lastAttemptAt": now,
                "updatedAt": now
            }
        )

        return data

    return claim(transaction)


def _get_period_notifications(
    db,
    recipient_id: str,
    period_started_at,
    period_ended_at
):
    """
    Retrieve notifications created during the current digest period.

    The end boundary is exclusive. Notifications created at or after
    that boundary belong to the next digest period.
    Read status does not affect inclusion.
    """

    query = (
        db.collection(NOTIFICATION_COLLECTION)
        .where(
            filter=FieldFilter(
                "recipientID", "==", recipient_id
            )
        )
        .where(
            filter=FieldFilter(
                "createdAt", ">=", period_started_at
            )
        )
        .where(
            filter=FieldFilter(
                "createdAt", "<", period_ended_at
            )
        )
    )

    return [
        document.to_dict()
        for document in query.stream()
    ]


def _complete_digest_cycle(
    db,
    digest_ref,
    period_ended_at,
    notification_count,
    email_sent
):
    """
    Complete the current digest period without deleting its tracking doc.

    Notifications arriving during email delivery remain eligible for
    the next period because its start time is set to period_ended_at.
    """

    transaction = db.transaction()

    @firestore.transactional
    def complete(transaction):
        snapshot = digest_ref.get(transaction=transaction)

        if not snapshot.exists:
            return False

        data = snapshot.to_dict() or {}

        if data.get("status") != "sending":
            return False

        processed_at = datetime.now(timezone.utc)

        updates = {
            "periodStartedAt": period_ended_at,
            "nextDigestAt": period_ended_at + timedelta(
                hours=DIGEST_INTERVAL_HOURS
            ),
            "status": "collecting",
            "leaseUntil": firestore.DELETE_FIELD,
            "lastError": firestore.DELETE_FIELD,
            "lastProcessedAt": processed_at,
            "lastNotificationCount": notification_count,
            "updatedAt": processed_at
        }

        if email_sent:
            updates["lastSentAt"] = processed_at

        transaction.update(digest_ref, updates)

        return True

    return complete(transaction)


def _release_digest(db, digest_ref, error_message=None):
    """
    Return a failed digest to the collecting state for retry.
    Its original period boundaries remain unchanged.
    """

    transaction = db.transaction()

    @firestore.transactional
    def release(transaction):
        snapshot = digest_ref.get(transaction=transaction)

        if not snapshot.exists:
            return

        data = snapshot.to_dict() or {}

        if data.get("status") != "sending":
            return

        transaction.update(
            digest_ref,
            {
                "status": "collecting",
                "leaseUntil": firestore.DELETE_FIELD,
                "lastError": (
                    error_message or "Digest processing failed."
                ),
                "updatedAt": datetime.now(timezone.utc)
            }
        )

    release(transaction)


def process_due_email_digests(db):
    """
    Process all due 72-hour notification digests.

    After processing, the recipient's tracking document is rolled
    forward into the next 72-hour collection period.
    """

    now = datetime.now(timezone.utc)

    statistics = {
        "checked": 0,
        "claimed": 0,
        "sent": 0,
        "skipped": 0,
        "failed": 0
    }

    digest_documents = (
        db.collection(DIGEST_COLLECTION).stream()
    )

    for digest_document in digest_documents:
        statistics["checked"] += 1

        digest_ref = digest_document.reference

        try:
            digest_data = _claim_digest(
                db,
                digest_ref,
                now
            )

            if digest_data is None:
                statistics["skipped"] += 1
                continue

            statistics["claimed"] += 1

            recipient_id = digest_data.get("recipientUID")
            period_started_at = digest_data.get("periodStartedAt")

            if not recipient_id or not period_started_at:
                raise ValueError(
                    "Digest recipient or period start is missing."
                )

            # Capture the collection boundary before retrieving
            # notifications or sending the email.
            period_ended_at = datetime.now(timezone.utc)

            user_snapshot = (
                db.collection(USER_COLLECTION)
                .document(recipient_id)
                .get()
            )

            if not user_snapshot.exists:
                raise ValueError(
                    "Recipient user profile does not exist."
                )

            user_data = user_snapshot.to_dict() or {}
            recipient_email = user_data.get("email")

            if not recipient_email:
                raise ValueError(
                    "Recipient email address is missing."
                )

            notifications = _get_period_notifications(
                db,
                recipient_id,
                period_started_at,
                period_ended_at
            )

            # Even an empty period must be rolled forward.
            # Deleting the tracking document here could lose
            # notifications arriving during processing.
            if not notifications:
                completed = _complete_digest_cycle(
                    db,
                    digest_ref,
                    period_ended_at,
                    notification_count=0,
                    email_sent=False
                )

                if not completed:
                    raise RuntimeError(
                        "Unable to complete empty digest period."
                    )

                statistics["skipped"] += 1
                continue

            send_notification_digest_email(
                recipient_email=recipient_email,
                notifications=notifications,
                period_started_at=period_started_at,
                period_ended_at=period_ended_at
            )

            # Roll the tracking document forward only after
            # SendGrid accepts the email.
            completed = _complete_digest_cycle(
                db,
                digest_ref,
                period_ended_at,
                notification_count=len(notifications),
                email_sent=True
            )

            if not completed:
                raise RuntimeError(
                    "Email was accepted, but digest rollover failed."
                )

            statistics["sent"] += 1

            logger.info(
                "Notification digest accepted for recipient UID: %s",
                recipient_id
            )

        except Exception:
            logger.exception(
                "Failed to process email digest: %s",
                digest_document.id
            )

            try:
                _release_digest(
                    db,
                    digest_ref,
                    "Digest delivery or processing failed."
                )
            except Exception:
                logger.exception(
                    "Unable to release digest for retry: %s",
                    digest_document.id
                )

            statistics["failed"] += 1

    return statistics