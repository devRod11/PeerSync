from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from google.cloud.firestore import SERVER_TIMESTAMP
from google.cloud.firestore_v1.base_query import FieldFilter
from app.database.firebase import get_firestore_client
from app.dependencies.auth import get_current_user, require_professor


router = APIRouter(prefix="/groups", tags=["Groups"])

class GroupCreate(BaseModel):
    projectID: str = Field(min_length=1)
    groupName: str = Field(min_length=1, max_length=100)
    memberIDs: list[str] = Field(default_factory=list, max_length=450)
    leaderID: Optional[str] = None


class GroupUpdate(BaseModel):
    groupName: Optional[str] = Field(
        default=None,
        min_length=1,
        max_length=100
    )


class GroupMembersAdd(BaseModel):
    memberIDs: list[str] = Field(min_length=1, max_length=450)


class GroupLeaderAssign(BaseModel):
    studentID: str = Field(min_length=1)

def get_group_or_404(db, group_id: str):
    group_ref = db.collection("groups").document(group_id)
    group_doc = group_ref.get()

    if not group_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Group not found."
        )

    return group_ref, group_doc.to_dict()


def get_project_or_404(db, project_id: str):
    project_ref = db.collection("projects").document(project_id)
    project_doc = project_ref.get()

    if not project_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Project not found."
        )

    return project_doc.to_dict()


def verify_project_ownership(project: dict, current_user: dict):
    if project.get("professorID") != current_user["uid"]:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to manage this project."
        )

def verify_group_professor_access(
    db,
    group_data: dict,
    current_user: dict
):
    if group_data.get("professorID") != current_user["uid"]:
        raise HTTPException(
            status_code=403,
            detail="You are not authorized to manage this group."
        )


def membership_document_id(group_id: str, student_id: str):
    return f"{group_id}_{student_id}"


def verify_student_accounts(db, student_ids: list[str]):
    for student_id in student_ids:
        student_doc = (
            db.collection("users")
            .document(student_id)
            .get()
        )

        if not student_doc.exists:
            raise HTTPException(
                status_code=404,
                detail=f"Student account {student_id} does not exist."
            )

        student_data = student_doc.to_dict()

        if student_data.get("role") != "student":
            raise HTTPException(
                status_code=400,
                detail=f"Account {student_id} is not a student."
            )

        if student_data.get("isActive") is not True:
            raise HTTPException(
                status_code=400,
                detail=f"Student account {student_id} is inactive."
            )

def get_project_group_assignments(db, project_id: str):
    membership_docs = (
        db.collection("group_members")
        .where(
            filter=FieldFilter("projectID", "==", project_id)
        )
        .stream()
    )

    assignments = {}

    for membership in membership_docs:
        data = membership.to_dict() or {}

        student_id = data.get("studentID")
        group_id = data.get("groupID")

        if student_id and group_id:
            assignments.setdefault(student_id, set()).add(group_id)

    return assignments


def verify_students_not_in_other_group(
    db,
    project_id: str,
    student_ids: list[str],
    target_group_id: Optional[str] = None
):
    assignments = get_project_group_assignments(
        db,
        project_id
    )

    conflicting_students = []

    for student_id in student_ids:
        assigned_groups = assignments.get(student_id, set())

        conflicting_groups = {
            group_id
            for group_id in assigned_groups
            if group_id != target_group_id
        }

        if conflicting_groups:
            conflicting_students.append(student_id)

    if conflicting_students:
        raise HTTPException(
            status_code=409,
            detail=(
                "The following student account(s) already belong "
                "to another group in this project: "
                + ", ".join(conflicting_students)
            )
        )

def get_group_members(db, group_id: str):
    membership_docs = (
        db.collection("group_members")
        .where(filter=FieldFilter("groupID", "==", group_id))
        .stream()
    )

    members = []

    for membership in membership_docs:
        data = membership.to_dict()
        student_id = data.get("studentID")

        # Retrieve the student's profile.
        user_doc = (
            db.collection("users")
            .document(student_id)
            .get()
        ) if student_id else None

        user_data = user_doc.to_dict() if user_doc and user_doc.exists else {}

        members.append({
            "membershipID": membership.id,
            "groupID": data.get("groupID"),
            "projectID": data.get("projectID"),
            "studentID": student_id,
            "displayName": user_data.get("displayName", "Unknown Student"),
            "email": user_data.get("email", ""),
            "memberRole": data.get("memberRole"),
            "joinedAt": data.get("joinedAt")
        })

    return members

def verify_group_membership(db, group_id: str, student_id: str):
    membership_docs = (
        db.collection("group_members")
        .where(
            filter=FieldFilter("groupID", "==", group_id)
        )
        .where(
            filter=FieldFilter("studentID", "==", student_id)
        )
        .limit(1)
        .get()
    )

    if not membership_docs:
        raise HTTPException(
            status_code=403,
            detail="You are not a member of this group."
        )

def get_group_response(db, group_id: str, group_data: dict):
    project_id = group_data.get("projectID")

    # Retrieve the associated project.
    project_info = None

    if project_id:
        project_doc = (
            db.collection("projects")
            .document(project_id)
            .get()
        )

        if project_doc.exists:
            project_data = project_doc.to_dict()

            project_info = {
                "id": project_doc.id,
                "title": project_data.get("title", "Untitled Project"),
                "academicYear": project_data.get("academicYear", ""),
                "status": project_data.get("status", "")
            }

    return {
        "id": group_id,
        **group_data,
        "project": project_info,
        "members": get_group_members(db, group_id)
    }

@router.post("/", status_code=status.HTTP_201_CREATED)
def create_group(
    request: GroupCreate,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    # Verify project existence and ownership.
    project = get_project_or_404(db, request.projectID)
    verify_project_ownership(project, current_user)

    member_ids = list(dict.fromkeys(request.memberIDs))

    # The selected leader must belong to the group.
    if request.leaderID and request.leaderID not in member_ids:
        raise HTTPException(
            status_code=400,
            detail="The Group Leader must be included in memberIDs."
        )

    verify_student_accounts(db, member_ids)

    verify_students_not_in_other_group(db, request.projectID, member_ids)

    if request.leaderID:
        verify_student_accounts(db, [request.leaderID])

    group_ref = db.collection("groups").document()

    group_data = {
        "groupName": request.groupName.strip(),
        "projectID": request.projectID,
        "professorID": current_user["uid"],
        "leaderID": request.leaderID,
        "memberIDs": member_ids,
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP
    }

    batch = db.batch()

    batch.set(group_ref, group_data)

    # Create membership documents.
    for student_id in member_ids:
        membership_ref = (
            db.collection("group_members")
            .document(
                membership_document_id(group_ref.id, student_id)
            )
        )

        member_role = (
            "Leader"
            if student_id == request.leaderID
            else "Member"
        )

        batch.set(membership_ref, {
            "groupID": group_ref.id,
            "projectID": request.projectID,
            "studentID": student_id,
            "memberRole": member_role,
            "joinedAt": SERVER_TIMESTAMP
        })

    batch.commit()

    created_group = group_ref.get().to_dict()

    return {
        "message": "Group created successfully.",
        "group": get_group_response(
            db,
            group_ref.id,
            created_group
        )
    }

@router.get("/")
def get_groups(
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()
    groups = []

    if current_user["role"] == "professor":

        group_docs = (
            db.collection("groups")
            .where(
                filter=FieldFilter(
                    "professorID",
                    "==",
                    current_user["uid"]
                )
            )
            .stream()
        )

        for group_doc in group_docs:
            groups.append(
                get_group_response(
                    db,
                    group_doc.id,
                    group_doc.to_dict()
                )
            )

    elif current_user["role"] == "student":

        membership_docs = (
            db.collection("group_members")
            .where(
                filter=FieldFilter(
                    "studentID",
                    "==",
                    current_user["uid"]
                )
            )
            .stream()
        )

        for membership in membership_docs:
            group_id = membership.to_dict().get("groupID")

            if not group_id:
                continue

            group_ref = db.collection("groups").document(group_id)
            group_doc = group_ref.get()

            if group_doc.exists:
                groups.append(
                    get_group_response(
                        db,
                        group_doc.id,
                        group_doc.to_dict()
                    )
                )

    else:
        raise HTTPException(
            status_code=403,
            detail="Invalid account role."
        )

    return {
        "count": len(groups),
        "groups": groups
    }

@router.get("/available-students")
def get_available_students(
    projectID: str = Query(..., min_length=1),
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    # Verify project existence and professor ownership.
    project = get_project_or_404(db, projectID)

    verify_project_ownership(
        project,
        current_user
    )

    # Retrieve students already assigned to groups
    # under this specific project.
    assignments = get_project_group_assignments(
        db,
        projectID
    )

    assigned_student_ids = set(assignments.keys())

    # Retrieve registered student accounts.
    student_docs = (
        db.collection("users")
        .where(
            filter=FieldFilter("role", "==", "student")
        )
        .stream()
    )

    students = []

    for student_doc in student_docs:
        student_data = student_doc.to_dict() or {}

        if student_data.get("isActive") is not True:
            continue

        # Exclude students already assigned to a group
        # in the selected project.
        if student_doc.id in assigned_student_ids:
            continue

        students.append({
            "uid": student_doc.id,
            "displayName": student_data.get(
                "displayName",
                "Unknown Student"
            ),
            "email": student_data.get("email", "")
        })

    students.sort(
        key=lambda student: student["displayName"].lower()
    )

    return {
        "count": len(students),
        "students": students
    }


@router.get("/{group_id}")
def get_group(
    group_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_firestore_client()

    group_ref, group_data = get_group_or_404(db, group_id)

    if current_user["role"] == "professor":
        verify_group_professor_access(
            db,
            group_data,
            current_user
        )

    elif current_user["role"] == "student":
        verify_group_membership(
            db,
            group_id,
            current_user["uid"]
        )

    else:
        raise HTTPException(
            status_code=403,
            detail="Invalid account role."
        )

    return {
        "group": get_group_response(
            db,
            group_ref.id,
            group_data
        )
    }

@router.put("/{group_id}")
def update_group(
    group_id: str,
    request: GroupUpdate,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    group_ref, group_data = get_group_or_404(db, group_id)

    verify_group_professor_access(
        db,
        group_data,
        current_user
    )

    update_data = request.model_dump(exclude_unset=True)

    if not update_data:
        raise HTTPException(
            status_code=400,
            detail="No update fields provided."
        )

    if "groupName" in update_data:
        if not update_data["groupName"].strip():
            raise HTTPException(
                status_code=400,
                detail="Group name cannot be empty."
            )

        update_data["groupName"] = update_data["groupName"].strip()

    update_data["updatedAt"] = SERVER_TIMESTAMP

    group_ref.update(update_data)

    return {
        "message": "Group updated successfully.",
        "group": get_group_response(
            db,
            group_id,
            group_ref.get().to_dict()
        )
    }

@router.post("/{group_id}/members")
def add_group_members(
    group_id: str,
    request: GroupMembersAdd,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    group_ref, group_data = get_group_or_404(db, group_id)

    verify_group_professor_access(
        db,
        group_data,
        current_user
    )

    new_student_ids = list(dict.fromkeys(request.memberIDs))

    verify_student_accounts(db, new_student_ids)

    existing_ids = set(group_data.get("memberIDs", []))

    students_to_add = [
        student_id
        for student_id in new_student_ids
        if student_id not in existing_ids
    ]

    verify_students_not_in_other_group(db, group_data["projectID"], students_to_add, target_group_id=group_id)

    if not students_to_add:
        raise HTTPException(
            status_code=409,
            detail="All specified students are already group members."
        )

    batch = db.batch()

    updated_member_ids = list(existing_ids) + students_to_add

    batch.update(group_ref, {
        "memberIDs": updated_member_ids,
        "updatedAt": SERVER_TIMESTAMP
    })

    for student_id in students_to_add:
        membership_ref = (
            db.collection("group_members")
            .document(
                membership_document_id(group_id, student_id)
            )
        )

        batch.set(membership_ref, {
            "groupID": group_id,
            "projectID": group_data["projectID"],
            "studentID": student_id,
            "memberRole": "Member",
            "joinedAt": SERVER_TIMESTAMP
        })

    batch.commit()

    return {
        "message": "Students added successfully.",
        "addedCount": len(students_to_add),
        "addedStudentIDs": students_to_add
    }

@router.put("/{group_id}/leader")
def assign_group_leader(
    group_id: str,
    request: GroupLeaderAssign,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    group_ref, group_data = get_group_or_404(db, group_id)

    verify_group_professor_access(
        db,
        group_data,
        current_user
    )

    student_id = request.studentID

    verify_student_accounts(db, [student_id])

    member_ids = group_data.get("memberIDs", [])

    if student_id not in member_ids:
        raise HTTPException(
            status_code=400,
            detail="The selected student is not a member of this group."
        )

    batch = db.batch()

    old_leader_id = group_data.get("leaderID")

    # Change the previous leader's membership role.
    if old_leader_id and old_leader_id != student_id:
        old_membership_ref = (
            db.collection("group_members")
            .document(
                membership_document_id(group_id, old_leader_id)
            )
        )

        batch.update(old_membership_ref, {
            "memberRole": "Member"
        })

    # Assign the new leader.
    new_membership_ref = (
        db.collection("group_members")
        .document(
            membership_document_id(group_id, student_id)
        )
    )

    batch.update(new_membership_ref, {
        "memberRole": "Leader"
    })

    batch.update(group_ref, {
        "leaderID": student_id,
        "updatedAt": SERVER_TIMESTAMP
    })

    batch.commit()

    return {
        "message": "Group Leader assigned successfully.",
        "groupID": group_id,
        "leaderID": student_id
    }

@router.delete("/{group_id}/members/{student_id}")
def remove_group_member(
    group_id: str,
    student_id: str,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    group_ref, group_data = get_group_or_404(db, group_id)

    verify_group_professor_access(
        db,
        group_data,
        current_user
    )

    member_ids = group_data.get("memberIDs", [])

    if student_id not in member_ids:
        raise HTTPException(
            status_code=404,
            detail="Student is not a member of this group."
        )

    membership_ref = (
        db.collection("group_members")
        .document(
            membership_document_id(group_id, student_id)
        )
    )

    membership_doc = membership_ref.get()

    if not membership_doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Group membership record not found."
        )

    updated_member_ids = [
        member for member in member_ids
        if member != student_id
    ]

    batch = db.batch()

    batch.update(group_ref, {
        "memberIDs": updated_member_ids,
        "updatedAt": SERVER_TIMESTAMP
    })

    batch.delete(membership_ref)

    # Clear leader designation if the removed student was the leader.
    if group_data.get("leaderID") == student_id:
        batch.update(group_ref, {
            "leaderID": None
        })

    batch.commit()

    return {
        "message": "Student removed from group successfully.",
        "groupID": group_id,
        "studentID": student_id
    }

@router.delete("/{group_id}")
def delete_group(
    group_id: str,
    current_user: dict = Depends(require_professor)
):
    db = get_firestore_client()

    group_ref, group_data = get_group_or_404(db, group_id)

    verify_group_professor_access(
        db,
        group_data,
        current_user
    )

    # Retrieve all membership records for this group.
    membership_docs = list(
        db.collection("group_members")
        .where(
            filter=FieldFilter("groupID", "==", group_id)
        )
        .stream()
    )

    batch = db.batch()

    for membership in membership_docs:
        batch.delete(membership.reference)

    batch.delete(group_ref)

    batch.commit()

    return {
        "message": "Group deleted successfully.",
        "groupID": group_id
    }