from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator
from google.cloud.firestore_v1.base_query import FieldFilter
from app.database.firebase import get_firestore_client
from app.dependencies.auth import get_current_user
from app.services.notification_service import (create_announcement_notifications, sync_announcement_notifications, delete_announcement_notifications)

router = APIRouter(
    prefix="/announcements",
    tags=["Announcements"]
)

class AnnouncementCreate(BaseModel):
    projectID: str
    targetType: str
    groupID: Optional[list[str]] = None
    title: str
    content: str

    @field_validator("projectID", "title", "content")
    @classmethod
    def validate_required_strings(cls, value):
        value = value.strip()

        if not value:
            raise ValueError("This field cannot be empty.")

        return value

    @field_validator("targetType")
    @classmethod
    def validate_target_type(cls, value):
        value = value.strip().lower()

        if value not in ["project", "group"]:
            raise ValueError(
                "targetType must be 'project' or 'group'."
            )

        return value

    @field_validator("groupID")
    @classmethod
    def validate_group_ids(cls, value):
        if value is not None:
            value = list(dict.fromkeys(
                group_id.strip()
                for group_id in value
                if group_id.strip()
            ))

        return value


class AnnouncementUpdate(BaseModel):
    targetType: Optional[str] = None
    groupID: Optional[list[str]] = None
    title: Optional[str] = None
    content: Optional[str] = None

    @field_validator("targetType")
    @classmethod
    def validate_target_type(cls, value):
        if value is not None:
            value = value.strip().lower()

            if value not in ["project", "group"]:
                raise ValueError(
                    "targetType must be 'project' or 'group'."
                )

        return value

    @field_validator("title", "content")
    @classmethod
    def validate_text_fields(cls, value):
        if value is not None:
            value = value.strip()

            if not value:
                raise ValueError("This field cannot be empty.")

        return value

    @field_validator("groupID")
    @classmethod
    def validate_group_ids(cls, value):
        if value is not None:
            value = list(dict.fromkeys(
                group_id.strip()
                for group_id in value
                if group_id.strip()
            ))

        return value

def get_db():
    return get_firestore_client()


def get_user_id(current_user: dict) -> str:
    user_id = (
        current_user.get("uid")
        or current_user.get("user_id")
        or current_user.get("sub")
    )

    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="Authenticated user ID not found."
        )

    return user_id


def get_user_role(current_user: dict) -> str:
    return str(current_user.get("role", "")).lower()


def get_project_or_404(db, project_id: str):
    doc = db.collection("projects").document(project_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Project not found."
        )

    return doc.to_dict()


def get_announcement_or_404(db, announcement_id: str):
    doc_ref = (
        db.collection("announcements")
        .document(announcement_id)
    )

    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Announcement not found."
        )

    return doc_ref, doc.to_dict()


def format_announcement(announcement_id: str, data: dict):
    return {
        "id": announcement_id,
        "authorID": data.get("authorID"),
        "content": data.get("content"),
        "createdAt": data.get("createdAt"),
        "groupID": data.get("groupID"),
        "projectID": data.get("projectID"),
        "targetType": data.get("targetType"),
        "title": data.get("title"),
        "updatedAt": data.get("updatedAt")
    }

def verify_professor_project_access(
    db,
    project_id: str,
    professor_id: str
):
    project = get_project_or_404(db, project_id)

    if project.get("professorID") != professor_id:
        raise HTTPException(
            status_code=403,
            detail="You do not have permission to manage this project."
        )

    return project

def verify_announcement_groups(
    db,
    project_id: str,
    target_type: str,
    group_ids: Optional[list[str]]
):
    if target_type == "project":
        if group_ids:
            raise HTTPException(
                status_code=400,
                detail="Project-wide announcements must have groupID set to null."
            )

        return

    if not group_ids:
        raise HTTPException(
            status_code=400,
            detail="At least one groupID is required for group announcements."
        )

    for group_id in group_ids:
        group_doc = (
            db.collection("groups")
            .document(group_id)
            .get()
        )

        if not group_doc.exists:
            raise HTTPException(
                status_code=404,
                detail=f"Group '{group_id}' not found."
            )

        group = group_doc.to_dict()

        if group.get("projectID") != project_id:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Group '{group_id}' does not belong "
                    "to the specified project."
                )
            )

def student_can_view_announcement(
    db,
    announcement: dict,
    student_id: str
) -> bool:
    project_id = announcement.get("projectID")
    target_type = announcement.get("targetType")
    target_groups = announcement.get("groupID") or []

    # Find the student's group memberships.
    memberships = (
        db.collection("group_members")
        .where(
            filter=FieldFilter(
                "studentID", "==", student_id
            )
        )
        .stream()
    )

    student_group_ids = {
        membership.to_dict().get("groupID")
        for membership in memberships
    }

    if target_type == "group":
        return bool(
            student_group_ids.intersection(target_groups)
        )

    if target_type == "project":
        # Check whether the student belongs to any group
        # under the announcement's project.
        project_groups = (
            db.collection("groups")
            .where(
                filter=FieldFilter(
                    "projectID", "==", project_id
                )
            )
            .stream()
        )

        project_group_ids = {
            group.id for group in project_groups
        }

        return bool(
            student_group_ids.intersection(project_group_ids)
        )

    return False


def verify_announcement_access(
    db,
    announcement: dict,
    current_user: dict
):
    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    if role == "professor":
        verify_professor_project_access(
            db,
            announcement["projectID"],
            user_id
        )

    elif role == "student":
        if not student_can_view_announcement(
            db,
            announcement,
            user_id
        ):
            raise HTTPException(
                status_code=403,
                detail="You cannot access this announcement."
            )

    else:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to access announcements."
        )

@router.post("/", status_code=201)
def create_announcement(
    announcement_data: AnnouncementCreate,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)

    if get_user_role(current_user) != "professor":
        raise HTTPException(
            status_code=403,
            detail="Only professors can create announcements."
        )

    verify_professor_project_access(
        db,
        announcement_data.projectID,
        user_id
    )

    verify_announcement_groups(
        db,
        announcement_data.projectID,
        announcement_data.targetType,
        announcement_data.groupID
    )

    now = datetime.now(timezone.utc)

    announcement = {
        "authorID": user_id,
        "content": announcement_data.content,
        "createdAt": now,
        "groupID": (
            announcement_data.groupID
            if announcement_data.targetType == "group"
            else None
        ),
        "projectID": announcement_data.projectID,
        "targetType": announcement_data.targetType,
        "title": announcement_data.title,
        "updatedAt": now
    }

    doc_ref = db.collection("announcements").document()
    doc_ref.set(announcement)

    notification_count = create_announcement_notifications(
        db,
        doc_ref.id,
        announcement
    )

    return {
        "message": "Announcement created successfully.",
        "announcement": format_announcement(
            doc_ref.id,
            announcement
        ),
        "notificationsCreated": notification_count
    }

@router.get("/")
def get_announcements(
    projectID: Optional[str] = Query(default=None),
    groupID: Optional[str] = Query(default=None),
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    announcements = []

    for doc in db.collection("announcements").stream():
        data = doc.to_dict()

        if projectID and data.get("projectID") != projectID:
            continue

        if groupID:
            requested_group = (
                db.collection("groups")
                .document(groupID)
                .get()
            )

            if (
                not requested_group.exists
                or requested_group.to_dict().get("projectID")
                != data.get("projectID")
            ):
                continue

            target_groups = data.get("groupID") or []

            if (
                data.get("targetType") == "group"
                and groupID not in target_groups
            ):
                continue

        if role == "professor":
            try:
                verify_professor_project_access(
                    db,
                    data["projectID"],
                    user_id
                )
            except HTTPException:
                continue

        elif role == "student":
            if not student_can_view_announcement(
                db,
                data,
                user_id
            ):
                continue

            # If a group filter is supplied, make sure the
            # student belongs to that group.
            if groupID:
                membership = (
                    db.collection("group_members")
                    .where(
                        filter=FieldFilter(
                            "groupID", "==", groupID
                        )
                    )
                    .where(
                        filter=FieldFilter(
                            "studentID", "==", user_id
                        )
                    )
                    .limit(1)
                    .get()
                )

                if not membership:
                    continue

        else:
            raise HTTPException(
                status_code=403,
                detail="You are not authorized to view announcements."
            )

        announcements.append(
            format_announcement(doc.id, data)
        )

    announcements.sort(
        key=lambda item: item.get("createdAt")
        or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True
    )

    return {
        "total": len(announcements),
        "announcements": announcements
    }

@router.get("/{announcement_id}")
def get_announcement(
    announcement_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    _, announcement = get_announcement_or_404(
        db,
        announcement_id
    )

    verify_announcement_access(
        db,
        announcement,
        current_user
    )

    return {
        "announcement": format_announcement(
            announcement_id,
            announcement
        )
    }

@router.put("/{announcement_id}")
def update_announcement(
    announcement_id: str,
    announcement_data: AnnouncementUpdate,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)

    if get_user_role(current_user) != "professor":
        raise HTTPException(
            status_code=403,
            detail="Only professors can update announcements."
        )

    doc_ref, existing = get_announcement_or_404(
        db,
        announcement_id
    )

    verify_professor_project_access(
        db,
        existing["projectID"],
        user_id
    )

    updates = announcement_data.model_dump(
        exclude_unset=True
    )

    if not updates:
        raise HTTPException(
            status_code=400,
            detail="No changes were provided."
        )

    # Validate the resulting announcement, not only
    # the fields included in the update request.
    new_target_type = updates.get(
        "targetType",
        existing.get("targetType")
    )

    new_group_ids = updates.get(
        "groupID",
        existing.get("groupID")
    )

    if new_target_type == "project":
        new_group_ids = None

    verify_announcement_groups(
        db,
        existing["projectID"],
        new_target_type,
        new_group_ids
    )

    updates["groupID"] = new_group_ids
    updates["updatedAt"] = datetime.now(timezone.utc)

    doc_ref.update(updates)
    updated_announcement = {
        **existing,
        **updates
    }

    notification_result = sync_announcement_notifications(
        db,
        announcement_id,
        updated_announcement
    )

    return {
        "message": "Announcement updated successfully.",
        "announcement": format_announcement(
            announcement_id,
            updated_announcement
        ),
        "notificationSync": notification_result
    }

@router.delete("/{announcement_id}")
def delete_announcement(
    announcement_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)

    if get_user_role(current_user) != "professor":
        raise HTTPException(
            status_code=403,
            detail="Only professors can delete announcements."
        )

    doc_ref, announcement = get_announcement_or_404(
        db,
        announcement_id
    )

    verify_professor_project_access(
        db,
        announcement["projectID"],
        user_id
    )

    deleted_notifications = delete_announcement_notifications(
        db,
        announcement_id
    )
    doc_ref.delete()

    return {
        "message": "Announcement deleted successfully.",
        "announcementID": announcement_id,
        "notificationsDeleted": deleted_notifications
    }