"""Firebase Cloud Messaging delivery for PeerSync.

Notifications are still written to the ``notifications`` collection (the in-app
list is the source of truth). This module adds an *optional* delivery channel:
when a student or professor has registered a device or browser, the same event
is also pushed through FCM so it reaches them when PeerSync is closed.

Every function here is best-effort. A missing FCM credential, an expired token
or a network error must never fail the API request that triggered it - the
in-app notification has already been committed by then.
"""

import logging
import hashlib

from firebase_admin import messaging

logger = logging.getLogger("peersync.push")

# FCM accepts at most 500 registration tokens per multicast request.
MAX_TOKENS_PER_REQUEST = 500

DEVICE_TOKENS_COLLECTION = "device_tokens"

def _short_id(value: str | None) -> str:
    """Return a shortened identifier for diagnostics without exposing the full ID."""
    if not value:
        return "unknown"
    return value[-6:]

def _token_fingerprint(token: str) -> str:
    """Return a safe, short fingerprint for correlating FCM logs."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:12]


def _chunks(items: list, size: int):
    for start in range(0, len(items), size):
        yield items[start:start + size]


def _get_device_token_records(db, user_ids) -> list[dict]:
    """Return registered device records for the supplied user IDs."""

    records_by_token: dict[str, dict] = {}
    unique_user_ids = {uid for uid in user_ids if uid}

    logger.info(
        "FCM targeting started | recipient_count=%d | recipients=%s",
        len(unique_user_ids),
        [_short_id(uid) for uid in unique_user_ids],
    )

    for user_id in unique_user_ids:
        try:
            docs = (
                db.collection(DEVICE_TOKENS_COLLECTION)
                .where("userID", "==", user_id)
                .stream()
            )

            user_device_count = 0

            for doc in docs:
                device = doc.to_dict() or {}
                token = device.get("token")

                if not token:
                    logger.warning(
                        "FCM device record has no token | user=%s | document=%s",
                        _short_id(user_id),
                        doc.id,
                    )
                    continue

                platform = device.get("platform") or "unknown"
                fingerprint = _token_fingerprint(token)

                user_device_count += 1

                if token not in records_by_token:
                    records_by_token[token] = {
                        "token": token,
                        "platform": platform,
                        "user_ids": {user_id},
                    }
                else:
                    records_by_token[token]["user_ids"].add(user_id)

                logger.info(
                    "FCM device matched | user=%s | platform=%s | token_id=%s",
                    _short_id(user_id),
                    platform,
                    fingerprint,
                )

            logger.info(
                "FCM user device lookup complete | user=%s | device_count=%d",
                _short_id(user_id),
                user_device_count,
            )

        except Exception:
            logger.exception(
                "Unable to read device tokens for user=%s",
                _short_id(user_id),
            )

    records = list(records_by_token.values())

    logger.info(
        "FCM device lookup summary | recipients=%d | unique_devices=%d | platforms=%s",
        len(unique_user_ids),
        len(records),
        {
            platform: sum(
                1 for record in records
                if record["platform"] == platform
            )
            for platform in {
                record["platform"] for record in records
            }
        },
    )

    return records


def get_device_tokens(db, user_ids) -> list[str]:
    """Return every registered token for the given user IDs (deduplicated)."""

    records = _get_device_token_records(db, user_ids)
    return [record["token"] for record in records]

def _delete_token(db, token: str) -> None:
    """Remove a token FCM reported as permanently invalid."""

    try:
        docs = (
            db.collection(DEVICE_TOKENS_COLLECTION)
            .where("token", "==", token)
            .stream()
        )

        for doc in docs:
            doc.reference.delete()
    except Exception:
        logger.exception("Unable to delete stale device token")



def _build_message(tokens: list[str], title: str, body: str, data: dict):
    return messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),

        # FCM requires every data value to be a string.
        data={key: str(value) for key, value in (data or {}).items()},

        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="peersync_updates",
                icon="ic_stat_peersync",
                color="#0A2342",
            ),
        ),

        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound="default", badge=1)
            )
        ),

        webpush=messaging.WebpushConfig(
            notification=messaging.WebpushNotification(
                icon="/icons/Icon-192.png",
                badge="/icons/favicon-48.png",
            ),
            fcm_options=messaging.WebpushFCMOptions(
                link="https://peersync-10.onrender.com/"
            ),
        ),
    )



def send_push_to_users(
    db,
    user_ids,
    title: str,
    body: str,
    data: dict | None = None,
) -> int:
    """Push title/body to every registered device of user_ids.

    Returns the number of successful FCM deliveries.
    """

    records = _get_device_token_records(db, user_ids)

    if not records:
        logger.warning(
            "FCM send skipped | reason=no_registered_devices"
        )
        return 0

    delivered = 0
    failed = 0

    logger.info(
        "FCM send started | devices=%d | title=%s",
        len(records),
        title,
    )

    for batch_number, batch_records in enumerate(
        _chunks(records, MAX_TOKENS_PER_REQUEST),
        start=1,
    ):
        batch_tokens = [
            record["token"] for record in batch_records
        ]

        logger.info(
            "FCM batch started | batch=%d | devices=%d | platforms=%s",
            batch_number,
            len(batch_records),
            {
                platform: sum(
                    1 for record in batch_records
                    if record["platform"] == platform
                )
                for platform in {
                    record["platform"] for record in batch_records
                }
            },
        )

        try:
            response = messaging.send_each_for_multicast(
                _build_message(
                    batch_tokens,
                    title,
                    body,
                    data or {},
                )
            )

        except Exception as exc:
            logger.exception(
                "FCM multicast request failed | batch=%d | devices=%d | error_type=%s",
                batch_number,
                len(batch_records),
                type(exc).__name__,
            )
            failed += len(batch_records)
            continue

        delivered += response.success_count
        failed += response.failure_count

        logger.info(
            "FCM batch result | batch=%d | success=%d | failure=%d",
            batch_number,
            response.success_count,
            response.failure_count,
        )

        for index, result in enumerate(response.responses):
            record = batch_records[index]
            token = record["token"]
            platform = record["platform"]
            fingerprint = _token_fingerprint(token)

            if result.success:
                logger.info(
                    "FCM device delivery accepted | platform=%s | token_id=%s | message_id=%s",
                    platform,
                    fingerprint,
                    result.message_id,
                )
                continue

            error = result.exception

            logger.error(
                "FCM device delivery failed | platform=%s | token_id=%s | error_type=%s | error_code=%s | error=%s",
                platform,
                fingerprint,
                type(error).__name__ if error else "unknown",
                getattr(error, "code", None),
                str(error),
            )

            if isinstance(
                error,
                (
                    messaging.UnregisteredError,
                    messaging.SenderIdMismatchError,
                ),
            ):
                logger.warning(
                    "Removing invalid FCM device token | platform=%s | token_id=%s",
                    platform,
                    fingerprint,
                )
                _delete_token(db, token)

    logger.info(
        "FCM send completed | attempted=%d | successful=%d | failed=%d",
        len(records),
        delivered,
        failed,
    )

    return delivered


def send_push_to_topic(
    topic: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> bool:
    """Fallback channel when a user has no registered device token.

    Clients subscribe to ``role_students`` / ``role_professors`` / ``all_users``
    on sign-in, so a topic send still reaches installed apps.
    """

    try:
        messaging.send(
            messaging.Message(
                topic=topic,
                notification=messaging.Notification(title=title, body=body),
                data={key: str(value) for key, value in (data or {}).items()},
            )
        )
        return True
    except Exception:
        logger.exception("FCM topic send failed for %s", topic)
        return False


def send_announcement_push(db, announcement_id: str, announcement: dict) -> int:
    """Push a newly published announcement to its eligible students only."""

    from app.services.notification_service import (
        _get_announcement_recipient_ids,
    )

    logger.info(
        "Announcement FCM requested | announcement_id=%s | title=%s",
        announcement_id,
        announcement.get("title") or "(untitled)",
    )

    try:
        recipient_ids = _get_announcement_recipient_ids(db, announcement)
    except Exception:
        logger.exception(
            "Unable to resolve announcement recipients | announcement_id=%s",
            announcement_id,
        )
        return 0

    logger.info(
        "Announcement FCM recipients resolved | announcement_id=%s | recipient_count=%d | recipients=%s",
        announcement_id,
        len(recipient_ids),
        [_short_id(uid) for uid in recipient_ids if uid],
    )

    if not recipient_ids:
        logger.warning(
            "Announcement FCM skipped | announcement_id=%s | reason=no_recipients",
            announcement_id,
        )
        return 0

    title = "New announcement"
    body = announcement.get("title") or "A new announcement has been published."

    delivered = send_push_to_users(
        db,
        recipient_ids,
        title,
        body,
        data={
            "type": "announcement_created",
            "destination": "announcements",
            "relatedDocumentID": announcement_id,
            "relatedCollections": "announcements",
        },
    )

    logger.info(
        "Announcement FCM completed | announcement_id=%s | recipients=%d | successful_device_deliveries=%d",
        announcement_id,
        len(recipient_ids),
        delivered,
    )

    return delivered


def send_task_assignment_push(
    db,
    task_id: str,
    assigned_to: list[str],
    task_title: str,
) -> int:
    """Push a task assignment to the newly assigned students."""

    if not assigned_to:
        return 0

    return send_push_to_users(
        db,
        assigned_to,
        "New task assigned",
        f"You have been assigned a new task: {task_title}.",
        data={
            "type": "task_assigned",
            "destination": "activities",
            "relatedDocumentID": task_id,
            "relatedCollections": "tasks",
        },
    )
