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

from firebase_admin import messaging

logger = logging.getLogger("peersync.push")

# FCM accepts at most 500 registration tokens per multicast request.
MAX_TOKENS_PER_REQUEST = 500

DEVICE_TOKENS_COLLECTION = "device_tokens"


def _chunks(items: list, size: int):
    for start in range(0, len(items), size):
        yield items[start:start + size]


def get_device_tokens(db, user_ids) -> list[str]:
    """Return every registered token for the given user IDs (deduplicated)."""

    tokens: list[str] = []

    for user_id in set(user_ids):
        if not user_id:
            continue

        try:
            docs = (
                db.collection(DEVICE_TOKENS_COLLECTION)
                .where("userID", "==", user_id)
                .stream()
            )

            for doc in docs:
                token = (doc.to_dict() or {}).get("token")

                if token:
                    tokens.append(token)
        except Exception:
            logger.exception("Unable to read device tokens for %s", user_id)

    # Preserve order while removing duplicates.
    return list(dict.fromkeys(tokens))


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
            fcm_options=messaging.WebpushFCMOptions(link="/"),
        ),
    )


def send_push_to_users(
    db,
    user_ids,
    title: str,
    body: str,
    data: dict | None = None,
) -> int:
    """Push ``title``/``body`` to every registered device of ``user_ids``.

    Returns the number of successful deliveries.
    """

    tokens = get_device_tokens(db, user_ids)

    if not tokens:
        return 0

    delivered = 0

    for batch in _chunks(tokens, MAX_TOKENS_PER_REQUEST):
        try:
            response = messaging.send_each_for_multicast(
                _build_message(batch, title, body, data or {})
            )
        except Exception:
            logger.exception("FCM multicast failed for %d token(s)", len(batch))
            continue

        delivered += response.success_count

        for index, result in enumerate(response.responses):
            if result.success:
                continue

            if isinstance(
                result.exception,
                (messaging.UnregisteredError, messaging.SenderIdMismatchError),
            ):
                _delete_token(db, batch[index])
            else:
                logger.warning(
                    "FCM delivery failed: %s", result.exception
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
    """Push a newly published announcement to its eligible students only.

    Reuses the recipient resolution from ``notification_service`` so the push
    audience is exactly the same set that received an in-app notification -
    professors are never included, and students outside the target group are
    never included.
    """

    # Imported lazily to avoid a circular import at module load time.
    from app.services.notification_service import (
        _get_announcement_recipient_ids,
    )

    try:
        recipient_ids = _get_announcement_recipient_ids(db, announcement)
    except Exception:
        logger.exception("Unable to resolve announcement recipients")
        return 0

    if not recipient_ids:
        return 0

    title = "New announcement"
    body = announcement.get("title") or "A new announcement has been published."

    return send_push_to_users(
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
