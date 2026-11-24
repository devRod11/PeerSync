from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.database.firebase import get_firestore_client
from app.dependencies.auth import (
    get_current_user,
    require_professor,
)

router = APIRouter(
    prefix="/projects",
    tags=["Projects"]
)

class ProjectCreate(BaseModel):
    title: str
    description: str
    academicYear: str
    status: str = "ongoing"

class ProjectUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    academicYear: Optional[str] = None
    status: Optional[str] = None

def serialize_project(document):
    """
    Convert a Firestore project document into
    a JSON-compatible dictionary.
    """

    project_data = document.to_dict() or {}

    for field in ["createdAt", "updatedAt"]:
        value = project_data.get(field)

        if value is not None and hasattr(value, "isoformat"):
            project_data[field] = value.isoformat()

    return {
        "id": document.id,
        **project_data
    }


def get_project_or_404(db, project_id: str):
    """
    Retrieve a project or return HTTP 404.
    """

    document = (
        db.collection("projects")
        .document(project_id)
        .get()
    )

    if not document.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found."
        )

    return document


def student_can_access_project(db, student_id: str, project_id: str):
    """
    Check whether a Student belongs to a group
    associated with the specified project.
    """

    memberships = (
        db.collection("group_members")
        .where("studentId", "==", student_id)
        .get()
    )

    for membership in memberships:
        membership_data = membership.to_dict() or {}
        group_id = membership_data.get("groupId")

        if not group_id:
            continue

        group_document = (
            db.collection("groups")
            .document(str(group_id))
            .get()
        )

        if not group_document.exists:
            continue

        group_data = group_document.to_dict() or {}

        if str(group_data.get("projectId")) == project_id:
            return True

    return False


def verify_project_access(db, project_document, current_user):
    """
    Allow Professors to access their own projects.
    Allow Students to access projects associated
    with their group membership.
    """

    project_data = project_document.to_dict() or {}
    project_id = project_document.id

    if current_user["role"] == "professor":
        if project_data.get("professorID") != current_user["uid"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have access to this project."
            )

    elif current_user["role"] == "student":
        if not student_can_access_project(
            db,
            current_user["uid"],
            project_id
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have access to this project."
            )

    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied."
        )

@router.post("/", status_code=status.HTTP_201_CREATED)
def create_project(
    project: ProjectCreate,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    project_data = {
        "title": project.title,
        "description": project.description,
        "academicYear": project.academicYear,
        "professorID": current_user["uid"],
        "status": project.status,
        "createdAt": __import__("google.cloud.firestore").cloud.firestore.SERVER_TIMESTAMP,
        "updatedAt": __import__("google.cloud.firestore").cloud.firestore.SERVER_TIMESTAMP,
    }

    document_reference = (
        db.collection("projects")
        .document()
    )

    document_reference.set(project_data)

    created_document = document_reference.get()

    return {
        "message": "Project created successfully.",
        "project": serialize_project(created_document)
    }

@router.get("/")
def get_projects(
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    projects_collection = db.collection("projects")

    if current_user["role"] == "professor":

        documents = (
            projects_collection
            .where("professorID", "==", current_user["uid"])
            .get()
        )

        return {
            "count": len(documents),
            "projects": [
                serialize_project(document)
                for document in documents
            ]
        }

    memberships = (
        db.collection("group_members")
        .where("studentId", "==", current_user["uid"])
        .get()
    )

    accessible_project_ids = set()

    for membership in memberships:
        membership_data = membership.to_dict() or {}
        group_id = membership_data.get("groupId")

        if not group_id:
            continue

        group_document = (
            db.collection("groups")
            .document(str(group_id))
            .get()
        )

        if group_document.exists:
            group_data = group_document.to_dict() or {}
            project_id = group_data.get("projectId")

            if project_id:
                accessible_project_ids.add(str(project_id))

    accessible_projects = []

    for project_id in accessible_project_ids:
        document = (
            projects_collection
            .document(project_id)
            .get()
        )

        if document.exists:
            accessible_projects.append(
                serialize_project(document)
            )

    return {
        "count": len(accessible_projects),
        "projects": accessible_projects
    }

@router.get("/{project_id}")
def get_project(
    project_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    document = get_project_or_404(db, project_id)

    verify_project_access(
        db,
        document,
        current_user
    )

    return {
        "project": serialize_project(document)
    }

@router.put("/{project_id}")
def update_project(
    project_id: str,
    project: ProjectUpdate,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    document = get_project_or_404(db, project_id)
    project_data = document.to_dict() or {}

    if project_data.get("professorID") != current_user["uid"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only update your own projects."
        )

    update_data = project.model_dump(exclude_unset=True)

    if not update_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No project fields were provided for updating."
        )

    update_data["updatedAt"] = (
        __import__("google.cloud.firestore").cloud.firestore.SERVER_TIMESTAMP
    )

    (
        db.collection("projects")
        .document(project_id)
        .update(update_data)
    )

    updated_document = (
        db.collection("projects")
        .document(project_id)
        .get()
    )

    return {
        "message": "Project updated successfully.",
        "project": serialize_project(updated_document)
    }

@router.delete("/{project_id}")
def delete_project(
    project_id: str,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    document = get_project_or_404(db, project_id)
    project_data = document.to_dict() or {}

    if project_data.get("professorID") != current_user["uid"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only delete your own projects."
        )

        # Prevent deletion if related records exist.
    dependent_collections = [
        "groups",
        "milestones",
        "tasks",
        "submissions"
    ]

    for collection_name in dependent_collections:
        related_documents = (
            db.collection(collection_name)
            .where("projectID", "==", project_id)
            .limit(1)
            .get()
        )

        if related_documents:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "This project cannot be deleted because "
                    f"related records exist in '{collection_name}'."
                )
            )

    db.collection("projects").document(project_id).delete()

    return {
        "message": "Project deleted successfully.",
        "projectId": project_id
    }
