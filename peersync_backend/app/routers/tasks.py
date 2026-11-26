import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, Field, field_validator

from app.database.firebase import get_firestore_client
from app.dependencies.auth import get_current_user
from app.services.notification_service import create_task_assignment_notifications
from app.services.push_service import send_task_assignment_push
from app.services.task_status_service import recalculate_task_status
from app.services.calendar_sync_service import (
    sync_resource_calendar_events,
    delete_resource_calendar_events,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/tasks", tags=["Tasks"])

VALID_PRIORITIES = ["Low", "Medium", "High"]
VALID_STATUSES = ["pending", "in_progress", "completed"]

class TaskCreate(BaseModel):
    projectID: str
    groupID: str
    milestoneID: str
    assignedTo: list[str] = Field(min_length=1)
    title: str = Field(min_length=1)
    description: str = Field(min_length=1)
    dueDate: datetime
    priority: str = "Medium"

    @field_validator("projectID", "groupID", "milestoneID", "title", "description")
    @classmethod
    def validate_non_empty_strings(cls, value):
        if not value.strip():
            raise ValueError("This field cannot be empty.")
        return value.strip()

    @field_validator("assignedTo")
    @classmethod
    def validate_assigned_students(cls, value):
        if not value:
            raise ValueError("At least one Student must be assigned.")

        if len(value) != len(set(value)):
            raise ValueError("Duplicate Student IDs are not allowed.")

        return value

    @field_validator("priority")
    @classmethod
    def validate_priority(cls, value):
        value = value.capitalize()

        if value not in VALID_PRIORITIES:
            raise ValueError(
                "Priority must be Low, Medium, or High."
            )

        return value


class TaskUpdate(BaseModel):
    assignedTo: Optional[list[str]] = Field(default=None, min_length=1)
    title: Optional[str] = None
    description: Optional[str] = None
    dueDate: Optional[datetime] = None
    priority: Optional[str] = None

    @field_validator("assignedTo")
    @classmethod
    def validate_assigned_students(cls, value):
        if value is not None and len(value) != len(set(value)):
            raise ValueError("Duplicate Student IDs are not allowed.")
        return value

    @field_validator("title", "description")
    @classmethod
    def validate_non_empty_strings(cls, value):
        if value is not None and not value.strip():
            raise ValueError("This field cannot be empty.")
        return value.strip() if value is not None else value

    @field_validator("priority")
    @classmethod
    def validate_priority(cls, value):
        if value is None:
            return value

        value = value.capitalize()

        if value not in VALID_PRIORITIES:
            raise ValueError(
                "Priority must be Low, Medium, or High."
            )

        return value


class TaskStatusUpdate(BaseModel):
    status: str

    @field_validator("status")
    @classmethod
    def validate_status(cls, value):
        value = value.lower()

        if value not in VALID_STATUSES:
            raise ValueError(
                "Status must be pending, in_progress, or completed."
            )

        return value

def get_task_or_404(db, task_id: str):
    doc = db.collection("tasks").document(task_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Task not found."
        )

    return doc


def get_project_or_404(db, project_id: str):
    doc = db.collection("projects").document(project_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Project not found."
        )

    return doc.to_dict()


def get_group_or_404(db, group_id: str):
    doc = db.collection("groups").document(group_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Group not found."
        )

    return doc.to_dict()


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


def verify_group_project_relationship(
    db,
    group_id: str,
    project_id: str
):
    group = get_group_or_404(db, group_id)

    if group.get("projectID") != project_id:
        raise HTTPException(
            status_code=400,
            detail="The group does not belong to the specified project."
        )

    return group


def verify_milestone_relationship(
    db,
    milestone_id: str,
    project_id: str,
    group_id: str
):
    doc = (
        db.collection("milestones")
        .document(milestone_id)
        .get()
    )

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Milestone not found."
        )

    milestone = doc.to_dict()

    if milestone.get("projectID") != project_id:
        raise HTTPException(
            status_code=400,
            detail="The milestone does not belong to this project."
        )

    assigned_groups = milestone.get("groupID", [])

    if group_id not in assigned_groups:
        raise HTTPException(
            status_code=400,
            detail="The milestone is not assigned to this group."
        )

    return milestone


def verify_student_group_membership(
    db,
    group_id: str,
    student_id: str
):
    membership = (
        db.collection("group_members")
        .where(filter=FieldFilter("groupID", "==", group_id))
        .where(filter=FieldFilter("studentID", "==", student_id))
        .limit(1)
        .get()
    )

    if not membership:
        raise HTTPException(
            status_code=403,
            detail="The Student is not a member of this group."
        )


def verify_assigned_students(
    db,
    group_id: str,
    assigned_to: list[str]
):
    for student_id in assigned_to:

        # Verify user account
        user_doc = (
            db.collection("users")
            .document(student_id)
            .get()
        )

        if not user_doc.exists:
            raise HTTPException(
                status_code=404,
                detail=f"Student account '{student_id}' not found."
            )

        user = user_doc.to_dict()

        if user.get("role") != "student":
            raise HTTPException(
                status_code=400,
                detail=f"User '{student_id}' is not a Student."
            )

        if user.get("isActive") is not True:
            raise HTTPException(
                status_code=400,
                detail=f"Student '{student_id}' is inactive."
            )

        # Verify group membership
        verify_student_group_membership(
            db,
            group_id,
            student_id
        )


def verify_group_leader(
    group: dict,
    user_id: str
):
    if group.get("leaderID") != user_id:
        raise HTTPException(
            status_code=403,
            detail="Only the Group Leader can perform this operation."
        )


def verify_task_access(
    db,
    task: dict,
    current_user: dict
):
    role = current_user["role"]
    user_id = current_user["uid"]

    if role == "professor":
        verify_professor_project_access(
            db,
            task["projectID"],
            user_id
        )
        return

    if role == "student":
        group = get_group_or_404(db, task["groupID"])

        # Group Leaders can access tasks in their own group.
        if group.get("leaderID") == user_id:
            return

        # Regular Students can access only tasks assigned to them.
        if user_id in task.get("assignedTo", []):
            return

    raise HTTPException(
        status_code=403,
        detail="You do not have permission to access this task."
    )


def format_task(doc):
    data = doc.to_dict()
    data["id"] = doc.id
    return data

def sync_task_calendar_safely(task_id: str, task: dict):
    """Synchronize task events without interrupting task operations."""

    try:
        sync_resource_calendar_events(
            resource_type="task",
            resource_id=task_id,
            student_uids=task.get("assignedTo", []),
            title=task.get("title", "Untitled Task"),
            description=task.get("description", ""),
            due_date=task.get("dueDate"),
            metadata={
                "Priority": task.get("priority"),
                "Status": task.get("status"),
            },
        )

    except Exception:
        logger.exception(
            "Unable to synchronize Google Calendar for task %s.",
            task_id,
        )


def delete_task_calendar_safely(task_id: str):
    """Delete task calendar events without interrupting task deletion."""

    try:
        delete_resource_calendar_events(
            resource_type="task",
            resource_id=task_id,
        )

    except Exception:
        logger.exception(
            "Unable to delete Google Calendar events for task %s.",
            task_id,
        )

@router.post("/", status_code=201)
def create_task(
    task_data: TaskCreate,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    user_id = current_user["uid"]
    role = current_user["role"]

    # Verify group and project relationship
    group = verify_group_project_relationship(
        db,
        task_data.groupID,
        task_data.projectID
    )

    # Verify creator's authority
    if role == "professor":

        verify_professor_project_access(
            db,
            task_data.projectID,
            user_id
        )

        created_by_role = "Professor"

    elif role == "student":

        verify_group_leader(
            group,
            user_id
        )

        created_by_role = "Leader"

    else:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to create tasks."
        )

    # Verify milestone belongs to the project and group
    verify_milestone_relationship(
        db,
        task_data.milestoneID,
        task_data.projectID,
        task_data.groupID
    )

    # Verify assigned Students
    verify_assigned_students(
        db,
        task_data.groupID,
        task_data.assignedTo
    )

    now = datetime.now(timezone.utc)

    task = {
        "assignedTo": task_data.assignedTo,
        "createdAt": now,
        "createdBy": user_id,
        "createdByRole": created_by_role,
        "description": task_data.description,
        "dueDate": task_data.dueDate,
        "groupID": task_data.groupID,
        "milestoneID": task_data.milestoneID,
        "priority": task_data.priority,
        "projectID": task_data.projectID,
        "status": "pending",
        "title": task_data.title,
        "updatedAt": now
    }

    doc_ref = db.collection("tasks").document()
    doc_ref.set(task)
    sync_task_calendar_safely(
        task_id=doc_ref.id,
        task=task,
    )

    create_task_assignment_notifications(
        db=db,
        task_id=doc_ref.id,
        assigned_to=task_data.assignedTo,
        task_title=task_data.title
    )

    send_task_assignment_push(
        db=db,
        task_id=doc_ref.id,
        assigned_to=task_data.assignedTo,
        task_title=task_data.title
    )

    return {
        "message": "Task created successfully.",
        "taskID": doc_ref.id,
        "task": {
            **task,
            "id": doc_ref.id
        }
    }

@router.get("/")
def get_tasks(
    projectID: Optional[str] = None,
    groupID: Optional[str] = None,
    milestoneID: Optional[str] = None,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    task_docs = db.collection("tasks").stream()

    results = []

    for doc in task_docs:
        task = doc.to_dict()

        if projectID and task.get("projectID") != projectID:
            continue

        if groupID and task.get("groupID") != groupID:
            continue

        if milestoneID and task.get("milestoneID") != milestoneID:
            continue

        try:
            verify_task_access(
                db,
                task,
                current_user
            )
        except HTTPException:
            continue

        results.append(format_task(doc))

    results.sort(
        key=lambda item: item.get("dueDate", datetime.max.replace(tzinfo=timezone.utc))
    )

    return {
        "total": len(results),
        "tasks": results
    }

@router.get("/{task_id}")
def get_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    doc = get_task_or_404(db, task_id)
    task = doc.to_dict()

    verify_task_access(
        db,
        task,
        current_user
    )

    return format_task(doc)



@router.put("/{task_id}")
def update_task(
    task_id: str,
    update_data: TaskUpdate,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    task_ref = db.collection("tasks").document(task_id)
    task_doc = task_ref.get()

    if not task_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Task not found."
        )

    task = task_doc.to_dict()

    user_id = current_user["uid"]
    role = current_user["role"]

    if role == "professor":

        verify_professor_project_access(
            db,
            task["projectID"],
            user_id
        )

    elif role == "student":

        group = get_group_or_404(db, task["groupID"])

        verify_group_leader(
            group,
            user_id
        )

    else:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to update task details."
        )

    updates = update_data.model_dump(exclude_unset=True)

    if not updates:
        raise HTTPException(
            status_code=400,
            detail="No update fields provided."
        )

    # Validate new assignments if supplied
    new_assigned_to = updates.get(
        "assignedTo",
        task.get("assignedTo", [])
    )

    verify_assigned_students(
        db,
        task["groupID"],
        new_assigned_to
    )

    # Identify newly assigned students
    previous_assignees = set(
        task.get("assignedTo", [])
    )

    updated_assignees = set(new_assigned_to)

    newly_assigned = list(
        updated_assignees - previous_assignees
    )

    updates["updatedAt"] = datetime.now(timezone.utc)

    # Save task updates first
    task_ref.update(updates)
    updated_task_data = {
        **task,
        **updates,
    }

    sync_task_calendar_safely(
        task_id=task_id,
        task=updated_task_data,
    )

    if "assignedTo" in updates:
        recalculate_task_status(
            db,
            task_id
        )

    # Notify only newly assigned students
    if newly_assigned:
        create_task_assignment_notifications(
            db=db,
            task_id=task_id,
            assigned_to=newly_assigned,
            task_title=updates.get(
                "title",
                task.get("title", "Untitled Task")
            )
        )

        send_task_assignment_push(
            db=db,
            task_id=task_id,
            assigned_to=newly_assigned,
            task_title=updates.get(
                "title",
                task.get("title", "Untitled Task")
            )
        )

    updated_doc = task_ref.get()

    return {
        "message": "Task updated successfully.",
        "task": format_task(updated_doc)
    }


@router.delete("/{task_id}")
def delete_task(
    task_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    task_ref = db.collection("tasks").document(task_id)
    task_doc = task_ref.get()

    if not task_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Task not found."
        )

    task = task_doc.to_dict()

    user_id = current_user["uid"]
    role = current_user["role"]

    if role == "professor":

        verify_professor_project_access(
            db,
            task["projectID"],
            user_id
        )

    elif role == "student":

        group = get_group_or_404(db, task["groupID"])

        verify_group_leader(
            group,
            user_id
        )

        if task.get("createdBy") != user_id:
            raise HTTPException(
                status_code=403,
                detail="You can only delete tasks that you created."
            )

    else:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to delete tasks."
        )

    task_ref.delete()
    delete_task_calendar_safely(task_id)

    return {
        "message": "Task deleted successfully.",
        "taskID": task_id
    }
