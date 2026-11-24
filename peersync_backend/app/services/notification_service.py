from datetime import datetime, timezone

from google.cloud.firestore_v1.base_query import FieldFilter


def create_task_assignment_notifications(
    db,
    task_id: str,
    assigned_to: list[str],
    task_title: str
):
    """
    Create one notification for each newly assigned student.
    """

    if not assigned_to:
        return 0

    notifications = db.collection("notifications")
    batch = db.batch()

    now = datetime.now(timezone.utc)
    created_count = 0

    for recipient_id in set(assigned_to):
        if not recipient_id:
            continue

        doc_ref = notifications.document()

        notification = {
            "Title": "New task assigned",
            "createdAt": now,
            "description": (
                f"You have been assigned a new task: {task_title}."
            ),
            "isRead": False,
            "recipientID": recipient_id,
            "relatedCollections": "tasks",
            "relatedDocumentID": task_id,
            "type": "task_assigned"
        }

        batch.set(doc_ref, notification)
        created_count += 1

    if created_count:
        batch.commit()

    return created_count

def _get_announcement_recipient_ids(
    db,
    announcement: dict
) -> set[str]:
    """
    Get all student UIDs currently eligible to receive
    an announcement notification.
    """

    project_id = announcement.get("projectID")
    target_type = announcement.get("targetType")

    if target_type == "project":
        groups = (
            db.collection("groups")
            .where(
                filter=FieldFilter(
                    "projectID", "==", project_id
                )
            )
            .stream()
        )

        group_ids = [group.id for group in groups]

    elif target_type == "group":
        group_ids = announcement.get("groupID") or []

    else:
        return set()

    recipient_ids = set()

    for group_id in group_ids:
        memberships = (
            db.collection("group_members")
            .where(
                filter=FieldFilter(
                    "groupID", "==", group_id
                )
            )
            .stream()
        )

        for membership in memberships:
            student_id = membership.to_dict().get("studentID")

            if student_id:
                recipient_ids.add(student_id)

    return recipient_ids


def _commit_notification_operations(db, operations):
    """
    Commit notification writes/deletes in batches of
    no more than 450 operations.
    
    Each operation is:
        ("set", document_reference, data)
        ("update", document_reference, data)
        ("delete", document_reference, None)
    """

    batch_size = 450
    committed_count = 0

    for start in range(0, len(operations), batch_size):
        batch = db.batch()

        current_operations = operations[
            start:start + batch_size
        ]

        for action, doc_ref, data in current_operations:
            if action == "set":
                batch.set(doc_ref, data)

            elif action == "update":
                batch.update(doc_ref, data)

            elif action == "delete":
                batch.delete(doc_ref)

        batch.commit()
        committed_count += len(current_operations)

    return committed_count


def create_announcement_notifications(
    db,
    announcement_id: str,
    announcement: dict
):
    """
    Create one notification for every student eligible
    to view the newly published announcement.
    """

    recipient_ids = _get_announcement_recipient_ids(
        db,
        announcement
    )

    notifications = db.collection("notifications")
    now = datetime.now(timezone.utc)

    operations = []

    for recipient_id in recipient_ids:
        doc_ref = notifications.document()

        notification = {
            "Title": "New announcement",
            "createdAt": now,
            "description": (
                f"A new announcement has been published: "
                f"{announcement.get('title', '')}. "
                f"{announcement.get('content', '')}"
            ),
            "isRead": False,
            "recipientID": recipient_id,
            "relatedCollections": "announcements",
            "relatedDocumentID": announcement_id,
            "type": "announcement_created"
        }

        operations.append(
            ("set", doc_ref, notification)
        )

    _commit_notification_operations(db, operations)

    return len(operations)


def sync_announcement_notifications(
    db,
    announcement_id: str,
    updated_announcement: dict
):
    """
    Synchronize announcement notifications with the
    announcement's current eligible recipients.

    - Retain and update notifications for existing recipients.
    - Create notifications for newly eligible recipients.
    - Delete notifications for recipients no longer eligible.
    - Preserve isRead for existing recipients.
    """

    notifications = db.collection("notifications")

    current_recipients = _get_announcement_recipient_ids(
        db,
        updated_announcement
    )

    existing_docs = (
        notifications
        .where(
            filter=FieldFilter(
                "relatedDocumentID", "==", announcement_id
            )
        )
        .stream()
    )

    existing_by_recipient = {}
    operations = []

    for doc in existing_docs:
        data = doc.to_dict()

        if data.get("relatedCollections") != "announcements":
            continue

        recipient_id = data.get("recipientID")

        if not recipient_id:
            continue

        # Store the existing notification document
        existing_by_recipient[recipient_id] = doc

    now = datetime.now(timezone.utc)

    for recipient_id, doc in existing_by_recipient.items():

        if recipient_id not in current_recipients:
            # The student is no longer eligible.
            operations.append(
                ("delete", doc.reference, None)
            )

        else:
            # Student remains eligible.
            # Updating these fields preserves isRead and createdAt.
            operations.append(
                (
                    "update",
                    doc.reference,
                    {
                        "Title": "Announcement updated",
                        "description": (
                            f"The announcement "
                            f"'{updated_announcement.get('title', '')}' "
                            f"has been updated. "
                            f"{updated_announcement.get('content', '')}"
                        ),
                        "type": "announcement_updated"
                    }
                )
            )

    for recipient_id in current_recipients:
        if recipient_id in existing_by_recipient:
            continue

        # Newly eligible student.
        doc_ref = notifications.document()

        notification = {
            "Title": "New announcement",
            "createdAt": now,
            "description": (
                f"A new announcement has been published: "
                f"{updated_announcement.get('title', '')}. "
                f"{updated_announcement.get('content', '')}"
            ),
            "isRead": False,
            "recipientID": recipient_id,
            "relatedCollections": "announcements",
            "relatedDocumentID": announcement_id,
            "type": "announcement_created"
        }

        operations.append(
            ("set", doc_ref, notification)
        )

    _commit_notification_operations(db, operations)

    return {
        "eligibleRecipients": len(current_recipients),
        "notificationOperations": len(operations)
    }


def delete_announcement_notifications(
    db,
    announcement_id: str
):
    """
    Delete all notifications associated with one announcement.
    Does not affect task or submission notifications.
    """

    notifications = db.collection("notifications")

    docs = (
        notifications
        .where(
            filter=FieldFilter(
                "relatedDocumentID", "==", announcement_id
            )
        )
        .stream()
    )

    operations = [
        ("delete", doc.reference, None)
        for doc in docs
        if doc.to_dict().get("relatedCollections") == "announcements"
    ]

    deleted_count = _commit_notification_operations(
        db,
        operations
    )

    return deleted_count