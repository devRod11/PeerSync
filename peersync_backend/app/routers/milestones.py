from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, Field, field_validator

from app.database.firebase import get_firestore_client
from app.dependencies.auth import (
    get_current_user,
    require_professor,
)

router = APIRouter(prefix="/milestones", tags=["Milestones"])

class MilestoneCreate(BaseModel):
    projectID: str
    groupID: list[str] = Field(min_length=1)
    title: str = Field(min_length=1)
    description: str = Field(min_length=1)
    sequence: int = Field(ge=1)
    startDate: datetime
    dueDate: datetime
    status: str = "pending"

    @field_validator("groupID")
    @classmethod
    def validate_group_ids(cls, value):
        if not value:
            raise ValueError("At least one group must be assigned.")

        if len(value) != len(set(value)):
            raise ValueError("Duplicate group IDs are not allowed.")

        return value

    @field_validator("title", "description", "projectID", "status")
    @classmethod
    def validate_non_empty_strings(cls, value):
        if not value.strip():
            raise ValueError("This field cannot be empty.")

        return value.strip()


class MilestoneUpdate(BaseModel):
    groupID: Optional[list[str]] = Field(default=None, min_length=1)
    title: Optional[str] = None
    description: Optional[str] = None
    sequence: Optional[int] = Field(default=None, ge=1)
    startDate: Optional[datetime] = None
    dueDate: Optional[datetime] = None
    status: Optional[str] = None

    @field_validator("groupID")
    @classmethod
    def validate_group_ids(cls, value):
        if value is not None and len(value) != len(set(value)):
            raise ValueError("Duplicate group IDs are not allowed.")
        return value

    @field_validator("title", "description", "status")
    @classmethod
    def validate_non_empty_strings(cls, value):
        if value is not None and not value.strip():
            raise ValueError("This field cannot be empty.")
        return value.strip() if value is not None else value

def get_milestone_or_404(db, milestone_id: str):
    doc = db.collection("milestones").document(milestone_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Milestone not found."
        )

    return doc.to_dict()


def get_project_or_404(db, project_id: str):
    doc = db.collection("projects").document(project_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Project not found."
        )

    return doc.to_dict()


def verify_project_ownership(db, project_id: str, professor_id: str):
    project = get_project_or_404(db, project_id)

    if project.get("professorID") != professor_id:
        raise HTTPException(
            status_code=403,
            detail="You do not have permission to manage this project."
        )

    return project


def verify_groups_belong_to_project(
    db,
    group_ids: list[str],
    project_id: str,
    professor_id: str
):
    for group_id in group_ids:
        group_doc = db.collection("groups").document(group_id).get()

        if not group_doc.exists:
            raise HTTPException(
                status_code=404,
                detail=f"Group '{group_id}' not found."
            )

        group = group_doc.to_dict()

        if group.get("projectID") != project_id:
            raise HTTPException(
                status_code=400,
                detail=f"Group '{group_id}' does not belong to this project."
            )

        if group.get("professorID") != professor_id:
            raise HTTPException(
                status_code=403,
                detail=f"You do not have permission to assign group '{group_id}'."
            )


def verify_student_milestone_access(
    db,
    milestone: dict,
    student_id: str
):
    assigned_group_ids = milestone.get("groupID", [])

    for group_id in assigned_group_ids:
        membership = (
            db.collection("group_members")
            .where(filter=FieldFilter("groupID", "==", group_id))
            .where(filter=FieldFilter("studentID", "==", student_id))
            .limit(1)
            .get()
        )

        if membership:
            return

    raise HTTPException(
        status_code=403,
        detail="You do not have access to this milestone."
    )


def format_milestone(doc):
    data = doc.to_dict()
    data["id"] = doc.id
    return data

@router.post("/", status_code=201)
def create_milestone(
    milestone_data: MilestoneCreate,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    professor_id = current_user["uid"]

    # Verify project ownership
    verify_project_ownership(
        db,
        milestone_data.projectID,
        professor_id
    )

    # Verify all assigned groups
    verify_groups_belong_to_project(
        db,
        milestone_data.groupID,
        milestone_data.projectID,
        professor_id
    )

    # Validate date range
    if milestone_data.startDate > milestone_data.dueDate:
        raise HTTPException(
            status_code=400,
            detail="The start date cannot be later than the due date."
        )

    now = datetime.now(timezone.utc)

    milestone = {
        "createdAt": now,
        "createdBy": professor_id,
        "description": milestone_data.description,
        "dueDate": milestone_data.dueDate,
        "groupID": milestone_data.groupID,
        "projectID": milestone_data.projectID,
        "sequence": milestone_data.sequence,
        "startDate": milestone_data.startDate,
        "status": milestone_data.status,
        "title": milestone_data.title,
        "updatedAt": now,
    }

    doc_ref = db.collection("milestones").document()
    doc_ref.set(milestone)

    return {
        "message": "Milestone created successfully.",
        "milestoneID": doc_ref.id,
        "milestone": {
            **milestone,
            "id": doc_ref.id
        }
    }

@router.get("/")
def get_milestones(
    projectID: Optional[str] = None,
    groupID: Optional[str] = None,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    milestone_docs = db.collection("milestones").stream()

    results = []

    for doc in milestone_docs:
        milestone = doc.to_dict()

        # Optional project filter
        if projectID and milestone.get("projectID") != projectID:
            continue

        # Optional group filter
        assigned_groups = milestone.get("groupID", [])

        if groupID and groupID not in assigned_groups:
            continue

        if current_user["role"] == "professor":
            # Professors can only see milestones
            # belonging to their own projects.
            project = db.collection("projects").document(
                milestone.get("projectID", "")
            ).get()

            if not project.exists:
                continue

            if project.to_dict().get("professorID") != current_user["uid"]:
                continue

        elif current_user["role"] == "student":
            # Students must belong to at least one
            # group assigned to the milestone.
            try:
                verify_student_milestone_access(
                    db,
                    milestone,
                    current_user["uid"]
                )
            except HTTPException:
                continue

        results.append(format_milestone(doc))

    results.sort(key=lambda item: item.get("sequence", 0))

    return {
        "total": len(results),
        "milestones": results
    }

@router.get("/{milestone_id}")
def get_milestone(
    milestone_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    milestone_doc = (
        db.collection("milestones")
        .document(milestone_id)
        .get()
    )

    if not milestone_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Milestone not found."
        )

    milestone = milestone_doc.to_dict()

    if current_user["role"] == "professor":
        verify_project_ownership(
            db,
            milestone["projectID"],
            current_user["uid"]
        )

    elif current_user["role"] == "student":
        verify_student_milestone_access(
            db,
            milestone,
            current_user["uid"]
        )

    return format_milestone(milestone_doc)

@router.put("/{milestone_id}")
def update_milestone(
    milestone_id: str,
    update_data: MilestoneUpdate,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    milestone_ref = db.collection("milestones").document(milestone_id)
    milestone_doc = milestone_ref.get()

    if not milestone_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Milestone not found."
        )

    existing = milestone_doc.to_dict()

    professor_id = current_user["uid"]

    # Verify ownership of the parent project
    verify_project_ownership(
        db,
        existing["projectID"],
        professor_id
    )

    updates = update_data.model_dump(exclude_unset=True)

    if not updates:
        raise HTTPException(
            status_code=400,
            detail="No update fields provided."
        )

    # Validate group assignments if provided
    new_group_ids = updates.get(
        "groupID",
        existing.get("groupID", [])
    )

    verify_groups_belong_to_project(
        db,
        new_group_ids,
        existing["projectID"],
        professor_id
    )

    # Validate combined date values
    new_start_date = updates.get(
        "startDate",
        existing["startDate"]
    )

    new_due_date = updates.get(
        "dueDate",
        existing["dueDate"]
    )

    if new_start_date > new_due_date:
        raise HTTPException(
            status_code=400,
            detail="The start date cannot be later than the due date."
        )

    # Backend controls the update timestamp.
    # It is independent of startDate and dueDate.
    updates["updatedAt"] = datetime.now(timezone.utc)

    milestone_ref.update(updates)

    updated_doc = milestone_ref.get()

    return {
        "message": "Milestone updated successfully.",
        "milestone": format_milestone(updated_doc)
    }

@router.delete("/{milestone_id}")
def delete_milestone(
    milestone_id: str,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    milestone_ref = db.collection("milestones").document(milestone_id)
    milestone_doc = milestone_ref.get()

    if not milestone_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Milestone not found."
        )

    milestone = milestone_doc.to_dict()

    verify_project_ownership(
        db,
        milestone["projectID"],
        current_user["uid"]
    )

    milestone_ref.delete()

    return {
        "message": "Milestone deleted successfully.",
        "milestoneID": milestone_id
    }
