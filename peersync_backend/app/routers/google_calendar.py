import logging
from fastapi import APIRouter, Depends, HTTPException, Query

from app.dependencies.auth import require_student
from app.integrations.google_calendar import (
    GoogleCalendarConfigurationError,
    GoogleCalendarOAuthError,
    create_authorization_url,
    exchange_authorization_code,
    get_google_calendar_status,
    disconnect_google_calendar,
)
from google.cloud.firestore_v1.base_query import FieldFilter
from app.database.firebase import get_firestore_client
from app.services.calendar_sync_service import sync_resource_calendar_events
logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/google-calendar",
    tags=["Google Calendar"],
)


@router.get("/oauth/authorize")
def authorize_google_calendar(
    current_user: dict = Depends(require_student),
):
    """Generate a Google Calendar authorization URL for the student."""

    try:
        authorization_url = create_authorization_url(
            current_user["uid"]
        )

        return {
            "message": "Google Calendar authorization URL generated.",
            "authorizationUrl": authorization_url,
        }

    except GoogleCalendarConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleCalendarOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None


@router.get("/oauth/callback")
def google_calendar_oauth_callback(
    code: str | None = Query(default=None),
    state: str | None = Query(default=None),
    error: str | None = Query(default=None),
):
    """
    Handle Google's OAuth redirect.

    Google redirects the browser here, so Firebase authentication
    is not required. The stored OAuth state identifies the student.
    """

    if error:
        raise HTTPException(
            status_code=400,
            detail="Google Calendar authorization was denied or cancelled.",
        )

    if not code or not state:
        raise HTTPException(
            status_code=400,
            detail="Missing authorization code or state.",
        )

    try:
        return exchange_authorization_code(
            code=code,
            state=state,
        )

    except GoogleCalendarConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleCalendarOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None


@router.get("/status")
def google_calendar_connection_status(
    current_user: dict = Depends(require_student),
):
    """Check the authenticated student's Calendar connection."""

    try:
        return get_google_calendar_status(
            current_user["uid"]
        )

    except GoogleCalendarConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleCalendarOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None


@router.delete("/disconnect")
def disconnect_student_google_calendar(
    current_user: dict = Depends(require_student),
):
    """Revoke and remove the authenticated student's connection."""

    try:
        return disconnect_google_calendar(
            current_user["uid"]
        )

    except GoogleCalendarConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleCalendarOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None

@router.post("/sync")
def sync_existing_calendar_events(
    current_user: dict = Depends(require_student),
):
    """Synchronize the student's existing tasks and milestones."""

    student_uid = current_user["uid"]

    # Confirm that the student has connected Google Calendar.
    try:
        calendar_status = get_google_calendar_status(student_uid)

        if not calendar_status.get("connected"):
            raise HTTPException(
                status_code=400,
                detail="Connect your Google Calendar before synchronizing.",
            )

    except GoogleCalendarConfigurationError as exc:
        raise HTTPException(
            status_code=500,
            detail=str(exc),
        ) from None

    except GoogleCalendarOAuthError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        ) from None

    db = get_firestore_client()

    synced_tasks = 0
    synced_milestones = 0
    failed_tasks = 0
    failed_milestones = 0

    # --------------------------------------------------
    # 1. Synchronize assigned tasks
    # --------------------------------------------------

    task_docs = (
        db.collection("tasks")
        .where(
            filter=FieldFilter(
                "assignedTo",
                "array_contains",
                student_uid,
            )
        )
        .stream()
    )

    for task_doc in task_docs:
        task = task_doc.to_dict()

        try:
            sync_resource_calendar_events(
                resource_type="task",
                resource_id=task_doc.id,
                student_uids=[student_uid],
                title=task.get("title", "Untitled Task"),
                description=task.get("description", ""),
                due_date=task.get("dueDate"),
                metadata={
                    "Priority": task.get("priority"),
                    "Status": task.get("status"),
                },
            )

            synced_tasks += 1

        except Exception:
            failed_tasks += 1

            logger.exception(
                "Initial Calendar synchronization failed for task %s.",
                task_doc.id,
            )

    # --------------------------------------------------
    # 2. Retrieve the student's group memberships
    # --------------------------------------------------

    membership_docs = (
        db.collection("group_members")
        .where(
            filter=FieldFilter(
                "studentID",
                "==",
                student_uid,
            )
        )
        .stream()
    )

    group_ids = set()

    for membership_doc in membership_docs:
        membership = membership_doc.to_dict()
        group_id = membership.get("groupID")

        if group_id:
            group_ids.add(group_id)

    # --------------------------------------------------
    # 3. Synchronize assigned milestones
    # --------------------------------------------------

    milestone_ids = set()

    for group_id in group_ids:
        milestone_docs = (
            db.collection("milestones")
            .where(
                filter=FieldFilter(
                    "groupID",
                    "array_contains",
                    group_id,
                )
            )
            .stream()
        )

        for milestone_doc in milestone_docs:
            milestone_ids.add(milestone_doc.id)

    for milestone_id in milestone_ids:
        milestone_doc = (
            db.collection("milestones")
            .document(milestone_id)
            .get()
        )

        if not milestone_doc.exists:
            continue

        milestone = milestone_doc.to_dict()

        try:
            sync_resource_calendar_events(
                resource_type="milestone",
                resource_id=milestone_id,
                student_uids=[student_uid],
                title=milestone.get("title", "Untitled Milestone"),
                description=milestone.get("description", ""),
                due_date=milestone.get("dueDate"),
                metadata={
                    "Project ID": milestone.get("projectID"),
                    "Sequence": milestone.get("sequence"),
                    "Start Date": milestone.get("startDate"),
                },
            )

            synced_milestones += 1

        except Exception:
            failed_milestones += 1

            logger.exception(
                "Initial Calendar synchronization failed for milestone %s.",
                milestone_id,
            )

    return {
        "message": "Google Calendar synchronization completed.",
        "tasks": {
            "attempted": synced_tasks + failed_tasks,
            "processed": synced_tasks,
            "failed": failed_tasks,
        },
        "milestones": {
            "attempted": synced_milestones + failed_milestones,
            "processed": synced_milestones,
            "failed": failed_milestones,
        },
    }