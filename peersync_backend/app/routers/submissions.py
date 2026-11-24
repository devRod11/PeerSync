from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, field_validator

from app.database.firebase import get_firestore_client
from app.dependencies.auth import get_current_user
from app.services.task_status_service import recalculate_task_status

router = APIRouter(prefix="/submissions", tags=["Submissions"])

VALID_REVIEW_STATUSES = ["approved", "revision_required"]

class SubmissionCreate(BaseModel):
    projectID: str
    groupID: str
    taskID: str
    fileName: str
    fileType: str

    @field_validator(
        "projectID",
        "groupID",
        "taskID",
        "fileName",
        "fileType"
    )
    @classmethod
    def validate_required_strings(cls, value):
        value = value.strip()

        if not value:
            raise ValueError("This field cannot be empty.")

        return value


class SubmissionReview(BaseModel):
    status: str
    feedback: Optional[str] = None

    @field_validator("status")
    @classmethod
    def validate_status(cls, value):
        value = value.strip().lower()

        if value not in VALID_REVIEW_STATUSES:
            raise ValueError(
                "Status must be approved or revision_required."
            )

        return value

    @field_validator("feedback")
    @classmethod
    def validate_feedback(cls, value):
        if value is not None:
            value = value.strip()

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


def get_submission_or_404(db, submission_id: str):
    doc_ref = db.collection("submissions").document(submission_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Submission not found."
        )

    return doc_ref, doc.to_dict()


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


def get_task_or_404(db, task_id: str):
    doc = db.collection("tasks").document(task_id).get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Task not found."
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
            detail="You do not have permission to access this project."
        )

    return project


def verify_group_membership(
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
            detail="You are not a member of this group."
        )


def verify_submission_access(
    db,
    submission: dict,
    current_user: dict
):
    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    if role == "professor":
        verify_professor_project_access(
            db,
            submission["projectID"],
            user_id
        )

    elif role == "student":
        # Students can only access their own submissions.
        if submission.get("submittedBy") != user_id:
            raise HTTPException(
                status_code=403,
                detail="You can only access your own submissions."
            )

        # Verify that the student still belongs to the group.
        verify_group_membership(
            db,
            submission["groupID"],
            user_id
        )

    else:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to access submissions."
        )

def format_submission(submission_id: str, data: dict):
    # Read the old misspelled field as a fallback,
    # but always return the corrected submittedAt field.
    submitted_at = data.get(
        "submittedAt",
        data.get("subittedAt")
    )

    return {
        "id": submission_id,
        "driveFileId": data.get("driveFileId"),
        "feedback": data.get("feedback"),
        "fileName": data.get("fileName"),
        "fileType": data.get("fileType"),
        "groupID": data.get("groupID"),
        "projectID": data.get("projectID"),
        "reviewedAt": data.get("reviewedAt"),
        "reviewedBy": data.get("reviewedBy"),
        "status": data.get("status"),
        "submittedAt": submitted_at,
        "submittedBy": data.get("submittedBy"),
        "taskID": data.get("taskID")
    }


def get_latest_student_submission(
    db,
    task_id: str,
    student_id: str
):
    docs = (
        db.collection("submissions")
        .where("taskID", "==", task_id)
        .where("submittedBy", "==", student_id)
        .stream()
    )

    submissions = [
        doc.to_dict()
        for doc in docs
    ]

    if not submissions:
        return None

    submissions.sort(
        key=lambda item: item.get("submittedAt")
        or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True
    )

    return submissions[0]

@router.post("/", status_code=201)
def create_submission(
    submission_data: SubmissionCreate,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    if role != "student":
        raise HTTPException(
            status_code=403,
            detail="Only students can submit deliverables."
        )

    # Validate project.
    get_project_or_404(db, submission_data.projectID)

    # Validate group and project relationship.
    group = get_group_or_404(
        db,
        submission_data.groupID
    )

    if group.get("projectID") != submission_data.projectID:
        raise HTTPException(
            status_code=400,
            detail="The group does not belong to this project."
        )

    # Validate student membership.
    verify_group_membership(
        db,
        submission_data.groupID,
        user_id
    )

    # Validate task and its relationships.
    task = get_task_or_404(
        db,
        submission_data.taskID
    )

    if (
        task.get("projectID") != submission_data.projectID
        or task.get("groupID") != submission_data.groupID
    ):
    
        raise HTTPException(
            status_code=400,
            detail="The task does not belong to the specified project and group."
        )

    # Only students assigned to the task can submit.
    assigned_students = task.get("assignedTo", [])

    if user_id not in assigned_students:
        raise HTTPException(
            status_code=403,
            detail="You are not assigned to this task."
        )


    # Check the student's latest submission for this task.
    latest_submission = get_latest_student_submission(
        db,
        submission_data.taskID,
        user_id
    )

    if latest_submission:
        latest_status = latest_submission.get("status")

        if latest_status == "pending":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Your previous submission is still pending review."
                )
            )

        if latest_status == "approved":
            raise HTTPException(
                status_code=400,
                detail=(
                    "This task has already been approved. "
                    "No further submission is allowed."
                )
            )

        if latest_status != "revision_required":
            raise HTTPException(
                status_code=400,
                detail="Invalid previous submission status."
            )

    now = datetime.now(timezone.utc)

    submission = {
        "driveFileId": None,
        "feedback": None,
        "fileName": submission_data.fileName,
        "fileType": submission_data.fileType,
        "groupID": submission_data.groupID,
        "projectID": submission_data.projectID,
        "reviewedAt": None,
        "reviewedBy": None,
        "status": "pending",
        "submittedAt": now,
        "submittedBy": user_id,
        "taskID": submission_data.taskID
    }

    doc_ref = db.collection("submissions").document()
    doc_ref.set(submission)

    doc_ref = db.collection("submissions").document()
    doc_ref.set(submission)

    recalculate_task_status(
        db,
        submission_data.taskID
    )

    return {
        "message": "Submission created successfully.",
        "submission": format_submission(
            doc_ref.id,
            submission
        )
    }

@router.get("/")
def get_submissions(
    projectID: Optional[str] = Query(default=None),
    groupID: Optional[str] = Query(default=None),
    taskID: Optional[str] = Query(default=None),
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    submissions = []

    for doc in db.collection("submissions").stream():
        data = doc.to_dict()

        # Apply optional filters.
        if projectID and data.get("projectID") != projectID:
            continue

        if groupID and data.get("groupID") != groupID:
            continue

        if taskID and data.get("taskID") != taskID:
            continue

        try:
            verify_submission_access(
                db,
                data,
                current_user
            )
        except HTTPException:
            continue

        submissions.append(
            format_submission(doc.id, data)
        )

    submissions.sort(
        key=lambda item: item.get("submittedAt")
        or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True
    )

    return {
        "total": len(submissions),
        "submissions": submissions
    }

@router.get("/{submission_id}")
def get_submission(
    submission_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    _, submission = get_submission_or_404(
        db,
        submission_id
    )

    verify_submission_access(
        db,
        submission,
        current_user
    )

    return {
        "submission": format_submission(
            submission_id,
            submission
        )
    }

@router.patch("/{submission_id}/review")
def review_submission(
    submission_id: str,
    review_data: SubmissionReview,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    if role != "professor":
        raise HTTPException(
            status_code=403,
            detail="Only professors can review submissions."
        )

    doc_ref, submission = get_submission_or_404(
        db,
        submission_id
    )

    # Verify that the professor owns the project.
    verify_professor_project_access(
        db,
        submission["projectID"],
        user_id
    )

    if submission.get("status") != "pending":
        raise HTTPException(
            status_code=400,
            detail="Only pending submissions can be reviewed."
        )

    if (
        review_data.status == "revision_required"
        and not review_data.feedback
    ):
        raise HTTPException(
            status_code=400,
            detail="Feedback is required when requesting a revision."
        )

    updates = {
        "status": review_data.status,
        "feedback": review_data.feedback,
        "reviewedAt": datetime.now(timezone.utc),
        "reviewedBy": user_id
    }

    doc_ref.update(updates)
    recalculate_task_status(
        db,
        submission["taskID"]
    )

    updated_submission = {
        **submission,
        **updates
    }

    return {
        "message": "Submission reviewed successfully.",
        "submission": format_submission(
            submission_id,
            updated_submission
        )
    }

@router.delete("/{submission_id}")
def delete_submission(
    submission_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    if role != "student":
        raise HTTPException(
            status_code=403,
            detail="Only the submitting student can delete a submission."
        )

    doc_ref, submission = get_submission_or_404(
        db,
        submission_id
    )

    if submission.get("submittedBy") != user_id:
        raise HTTPException(
            status_code=403,
            detail="You can only delete your own submissions."
        )

    if submission.get("status") != "pending":
        raise HTTPException(
            status_code=400,
            detail="Only pending submissions can be deleted."
        )

    doc_ref.delete()
    recalculate_task_status(
        db,
        submission["taskID"]
    )

    return {
        "message": "Submission deleted successfully.",
        "submissionID": submission_id
    }
