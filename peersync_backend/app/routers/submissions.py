from datetime import datetime, timezone
from typing import Optional
import io
import os
from urllib.parse import quote

from fastapi.responses import Response
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi import File, Form, UploadFile
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, field_validator

from app.database.firebase import get_firestore_client
from app.dependencies.auth import get_current_user
from app.services.task_status_service import recalculate_task_status
from app.integrations.google_drive import (
    GoogleDriveOAuthError,
    upload_drive_file,
    download_drive_file,
    delete_drive_file,
)

router = APIRouter(prefix="/submissions", tags=["Submissions"])

VALID_REVIEW_STATUSES = ["approved", "revision_required"]
MAX_UPLOAD_SIZE = 25 * 1024 * 1024  # 25 MB
ALLOWED_FILE_TYPES = {
    ".pdf": "application/pdf",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".ppt": "application/vnd.ms-powerpoint",
    ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".txt": "text/plain",
    ".csv": "text/csv",
    ".zip": "application/zip",
}

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

@router.post("/upload", status_code=201)
async def upload_submission(
    projectID: str = Form(...),
    groupID: str = Form(...),
    taskID: str = Form(...),
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    db = get_db()

    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    # Only students can upload deliverables.
    if role != "student":
        raise HTTPException(
            status_code=403,
            detail="Only students can submit deliverables."
        )

    # Validate the filename.
    original_name = file.filename or ""
    file_name = os.path.basename(
        original_name.replace("\\", "/")
    ).strip()

    if not file_name:
        raise HTTPException(
            status_code=400,
            detail="A valid filename is required."
        )

    extension = os.path.splitext(file_name)[1].lower()

    if extension not in ALLOWED_FILE_TYPES:
        raise HTTPException(
            status_code=400,
            detail="This file type is not supported."
        )

    mime_type = ALLOWED_FILE_TYPES[extension]

    # Read the uploaded file with a strict size limit.
    file_content = await file.read(MAX_UPLOAD_SIZE + 1)

    if not file_content:
        raise HTTPException(
            status_code=400,
            detail="The uploaded file is empty."
        )

    if len(file_content) > MAX_UPLOAD_SIZE:
        raise HTTPException(
            status_code=413,
            detail="File size exceeds the 25 MB limit."
        )

    # Validate project.
    get_project_or_404(db, projectID)

    # Validate group and project relationship.
    group = get_group_or_404(db, groupID)

    if group.get("projectID") != projectID:
        raise HTTPException(
            status_code=400,
            detail="The group does not belong to this project."
        )

    # Validate student membership.
    verify_group_membership(
        db,
        groupID,
        user_id
    )

    # Validate task and its relationships.
    task = get_task_or_404(db, taskID)

    if (
        task.get("projectID") != projectID
        or task.get("groupID") != groupID
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "The task does not belong to "
                "the specified project and group."
            )
        )

    # Only assigned students can submit.
    assigned_students = task.get("assignedTo", [])

    if user_id not in assigned_students:
        raise HTTPException(
            status_code=403,
            detail="You are not assigned to this task."
        )

    # Check the student's latest submission.
    latest_submission = get_latest_student_submission(
        db,
        taskID,
        user_id
    )

    if latest_submission:
        latest_status = latest_submission.get("status")

        if latest_status == "pending":
            raise HTTPException(
                status_code=409,
                detail=(
                    "Your previous submission "
                    "is still pending review."
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

    # Upload the actual file to Google Drive.
    try:
        uploaded_file = upload_drive_file(
            io.BytesIO(file_content),
            file_name,
            mime_type,
        )

    except GoogleDriveOAuthError:
        raise HTTPException(
            status_code=503,
            detail="Google Drive upload failed. Please try again."
        ) from None

    # Save submission metadata in Firestore.
    now = datetime.now(timezone.utc)

    submission = {
        "driveFileId": uploaded_file["driveFileId"],
        "feedback": None,
        "fileName": uploaded_file["fileName"],
        "fileType": mime_type,
        "groupID": groupID,
        "projectID": projectID,
        "reviewedAt": None,
        "reviewedBy": None,
        "status": "pending",
        "submittedAt": now,
        "submittedBy": user_id,
        "taskID": taskID,
    }

    doc_ref = db.collection("submissions").document()

    try:
        doc_ref.set(submission)

    except Exception:
        # Prevent an orphaned Drive file if Firestore fails.
        try:
            delete_drive_file(
                uploaded_file["driveFileId"]
            )
        except GoogleDriveOAuthError:
            pass

        raise HTTPException(
            status_code=500,
            detail="Unable to save submission metadata."
        ) from None

    recalculate_task_status(db, taskID)

    return {
        "message": "File uploaded and submission created successfully.",
        "submission": format_submission(
            doc_ref.id,
            submission
        ),
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

@router.get("/{submission_id}/download")
def download_submission(
    submission_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()

    user_id = get_user_id(current_user)
    role = get_user_role(current_user)

    # Only professors can download submissions through this endpoint.
    if role != "professor":
        raise HTTPException(
            status_code=403,
            detail="Only professors can download student submissions."
        )

    # Retrieve the submission from Firestore.
    _, submission = get_submission_or_404(
        db,
        submission_id
    )

    # Verify that the professor owns the associated project.
    verify_professor_project_access(
        db,
        submission["projectID"],
        user_id
    )

    # Retrieve the Drive ID from trusted Firestore metadata.
    drive_file_id = submission.get("driveFileId")

    if not drive_file_id:
        raise HTTPException(
            status_code=409,
            detail="This submission does not have an uploaded file."
        )

    # Retrieve the actual file from Google Drive.
    try:
        drive_file = download_drive_file(drive_file_id)

    except GoogleDriveOAuthError:
        raise HTTPException(
            status_code=503,
            detail="Unable to download the file from Google Drive."
        ) from None

    file_name = drive_file.get("fileName") or "submission"
    mime_type = (
        drive_file.get("mimeType")
        or "application/octet-stream"
    )
    file_content = drive_file.get("content")

    if file_content is None:
        raise HTTPException(
            status_code=502,
            detail="Google Drive returned an empty file response."
        )

    # Return the file as a downloadable response.
    return Response(
        content=file_content,
        media_type=mime_type,
        headers={
            "Content-Disposition": (
                f"attachment; filename*=UTF-8''{quote(file_name)}"
            ),
            "Cache-Control": "private, no-store",
            "X-Content-Type-Options": "nosniff",
        }
    )

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
