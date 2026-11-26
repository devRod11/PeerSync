import logging
from datetime import datetime, timedelta, timezone

from googleapiclient.errors import HttpError

from app.database.firebase import get_firestore_client
from app.integrations.google_calendar import (
    GoogleCalendarOAuthError,
    get_google_calendar_service,
)

logger = logging.getLogger(__name__)

EVENT_LINK_COLLECTION = "student_calendar_event_links"

# Google Calendar requires an end time.
EVENT_DURATION_MINUTES = 15


def _normalize_datetime(value):
    """Ensure a datetime is timezone-aware."""

    if not isinstance(value, datetime):
        raise ValueError("Calendar event dueDate must be a datetime.")

    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)

    return value


def _build_event(title, description, due_date, resource_type, metadata=None):
    """Build a timed Google Calendar event."""

    start_time = _normalize_datetime(due_date)
    end_time = start_time + timedelta(
        minutes=EVENT_DURATION_MINUTES
    )

    details = [
        description or "",
        "",
        f"PeerSync {resource_type.capitalize()}",
    ]

    for key, value in (metadata or {}).items():
        if value is not None:
            details.append(f"{key}: {value}")

    return {
        "summary": title,
        "description": "\n".join(details),
        "start": {
            "dateTime": start_time.isoformat(),
        },
        "end": {
            "dateTime": end_time.isoformat(),
        },
    }


def _get_link_ref(db, student_uid, resource_type, resource_id):
    """Get the Firestore mapping document for one event."""

    document_id = (
        f"{student_uid}_{resource_type}_{resource_id}"
    )

    return (
        db.collection(EVENT_LINK_COLLECTION)
        .document(document_id)
    )


def _upsert_student_event(
    db,
    student_uid,
    resource_type,
    resource_id,
    title,
    description,
    due_date,
    metadata=None,
):
    """Create or update one student's Google Calendar event."""

    link_ref = _get_link_ref(
        db,
        student_uid,
        resource_type,
        resource_id,
    )

    link_doc = link_ref.get()

    event_body = _build_event(
        title=title,
        description=description,
        due_date=due_date,
        resource_type=resource_type,
        metadata=metadata,
    )

    calendar_service = get_google_calendar_service(student_uid)

    event_id = None

    if link_doc.exists:
        event_id = link_doc.to_dict().get("googleEventID")

    if event_id:
        try:
            calendar_service.events().patch(
                calendarId="primary",
                eventId=event_id,
                body=event_body,
            ).execute()

        except HttpError as exc:
            if exc.resp.status != 404:
                raise

            # The event was deleted directly from Google Calendar.
            # Create a replacement event.
            event_id = None

    if not event_id:
        created_event = (
            calendar_service.events()
            .insert(
                calendarId="primary",
                body=event_body,
            )
            .execute()
        )

        event_id = created_event["id"]

    link_ref.set({
        "studentUID": student_uid,
        "resourceType": resource_type,
        "resourceID": resource_id,
        "googleEventID": event_id,
        "calendarID": "primary",
        "updatedAt": datetime.now(timezone.utc),
    }, merge=True)


def _delete_student_event(
    db,
    student_uid,
    resource_type,
    resource_id,
):
    """Delete one student's Google Calendar event and mapping."""

    link_ref = _get_link_ref(
        db,
        student_uid,
        resource_type,
        resource_id,
    )

    link_doc = link_ref.get()

    if not link_doc.exists:
        return

    link_data = link_doc.to_dict()
    event_id = link_data.get("googleEventID")

    if event_id:
        calendar_service = get_google_calendar_service(
            student_uid
        )

        try:
            calendar_service.events().delete(
                calendarId=link_data.get("calendarID", "primary"),
                eventId=event_id,
            ).execute()

        except HttpError as exc:
            # A missing Google event is already effectively deleted.
            if exc.resp.status != 404:
                raise

    link_ref.delete()


def sync_resource_calendar_events(
    resource_type,
    resource_id,
    student_uids,
    title,
    description,
    due_date,
    metadata=None,
):
    """
    Synchronize one task or milestone across its assigned students.

    Students without connected Google Calendars are skipped.
    Existing events for students no longer assigned are removed.
    """

    db = get_firestore_client()

    student_uids = set(student_uids or [])

    # Create or update events for currently assigned students.
    for student_uid in student_uids:
        try:
            _upsert_student_event(
                db=db,
                student_uid=student_uid,
                resource_type=resource_type,
                resource_id=resource_id,
                title=title,
                description=description,
                due_date=due_date,
                metadata=metadata,
            )

        except GoogleCalendarOAuthError:
            # The student has not connected or their authorization
            # needs attention. Do not interrupt PeerSync operations.
            logger.info(
                "Calendar sync skipped for student %s: "
                "Google Calendar is not available.",
                student_uid,
            )

        except Exception:
            logger.exception(
                "Calendar sync failed for student %s, %s %s.",
                student_uid,
                resource_type,
                resource_id,
            )

    # Find previously synchronized students.
    existing_links = (
        db.collection(EVENT_LINK_COLLECTION)
        .where("resourceType", "==", resource_type)
        .where("resourceID", "==", resource_id)
        .stream()
    )

    for link_doc in existing_links:
        link_data = link_doc.to_dict()
        previous_student_uid = link_data.get("studentUID")

        if previous_student_uid in student_uids:
            continue

        try:
            _delete_student_event(
                db=db,
                student_uid=previous_student_uid,
                resource_type=resource_type,
                resource_id=resource_id,
            )

        except GoogleCalendarOAuthError:
            logger.warning(
                "Unable to remove calendar event for student %s: "
                "Google Calendar authorization is unavailable.",
                previous_student_uid,
            )

        except Exception:
            logger.exception(
                "Calendar event removal failed for student %s, "
                "%s %s.",
                previous_student_uid,
                resource_type,
                resource_id,
            )


def delete_resource_calendar_events(resource_type, resource_id):
    """Remove all Google Calendar events associated with a resource."""

    db = get_firestore_client()

    existing_links = (
        db.collection(EVENT_LINK_COLLECTION)
        .where("resourceType", "==", resource_type)
        .where("resourceID", "==", resource_id)
        .stream()
    )

    for link_doc in existing_links:
        link_data = link_doc.to_dict()
        student_uid = link_data.get("studentUID")

        if not student_uid:
            continue

        try:
            _delete_student_event(
                db=db,
                student_uid=student_uid,
                resource_type=resource_type,
                resource_id=resource_id,
            )

        except GoogleCalendarOAuthError:
            logger.warning(
                "Unable to delete calendar event for student %s.",
                student_uid,
            )

        except Exception:
            logger.exception(
                "Calendar event deletion failed for student %s, "
                "%s %s.",
                student_uid,
                resource_type,
                resource_id,
            )