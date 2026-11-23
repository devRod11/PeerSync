from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from app.database.firebase import get_firestore_client
from app.dependencies.auth import get_current_user

router = APIRouter(
    prefix="/notifications",
    tags=["Notifications"]
)

class NotificationReadUpdate(BaseModel):
    isRead: bool

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


def get_notification_or_404(db, notification_id: str):
    doc_ref = (
        db.collection("notifications")
        .document(notification_id)
    )

    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(
            status_code=404,
            detail="Notification not found."
        )

    return doc_ref, doc.to_dict()


def verify_notification_owner(
    notification: dict,
    user_id: str
):
    if notification.get("recipientID") != user_id:
        raise HTTPException(
            status_code=403,
            detail="You cannot access this notification."
        )


def format_notification(notification_id: str, data: dict):
    return {
        "id": notification_id,
        "Title": data.get("Title"),
        "createdAt": data.get("createdAt"),
        "description": data.get("description"),
        "isRead": data.get("isRead", False),
        "recipientID": data.get("recipientID"),
        "relatedCollections": data.get("relatedCollections"),
        "relatedDocumentID": data.get("relatedDocumentID"),
        "type": data.get("type")
    }

@router.get("/")
def get_notifications(
    isRead: Optional[bool] = Query(default=None),
    current_user: dict = Depends(get_current_user)
):
    db = get_db()
    user_id = get_user_id(current_user)

    query = (
        db.collection("notifications")
        .where("recipientID", "==", user_id)
    )

    if isRead is not None:
        query = query.where("isRead", "==", isRead)

    notifications = []

    for doc in query.stream():
        notifications.append(
            format_notification(
                doc.id,
                doc.to_dict()
            )
        )

    notifications.sort(
        key=lambda item: item.get("createdAt")
        or 0,
        reverse=True
    )

    unread_count = sum(
        1 for item in notifications
        if not item["isRead"]
    )

    return {
        "total": len(notifications),
        "unreadCount": unread_count,
        "notifications": notifications
    }

@router.get("/{notification_id}")
def get_notification(
    notification_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()
    user_id = get_user_id(current_user)

    _, notification = get_notification_or_404(
        db,
        notification_id
    )

    verify_notification_owner(
        notification,
        user_id
    )

    return {
        "notification": format_notification(
            notification_id,
            notification
        )
    }

@router.patch("/read-all")
def mark_all_notifications_as_read(
    current_user: dict = Depends(get_current_user)
):
    db = get_db()
    user_id = get_user_id(current_user)

    docs = (
        db.collection("notifications")
        .where("recipientID", "==", user_id)
        .where("isRead", "==", False)
        .stream()
    )

    batch = db.batch()
    updated_count = 0

    for doc in docs:
        batch.update(doc.reference, {
            "isRead": True
        })
        updated_count += 1

    if updated_count:
        batch.commit()

    return {
        "message": "All notifications marked as read.",
        "updatedCount": updated_count
    }

@router.patch("/{notification_id}")
def update_notification_read_status(
    notification_id: str,
    update_data: NotificationReadUpdate,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()
    user_id = get_user_id(current_user)

    doc_ref, notification = get_notification_or_404(
        db,
        notification_id
    )

    verify_notification_owner(
        notification,
        user_id
    )

    doc_ref.update({
        "isRead": update_data.isRead
    })

    notification["isRead"] = update_data.isRead

    return {
        "message": "Notification status updated successfully.",
        "notification": format_notification(
            notification_id,
            notification
        )
    }

@router.delete("/{notification_id}")
def delete_notification(
    notification_id: str,
    current_user: dict = Depends(get_current_user)
):
    db = get_db()
    user_id = get_user_id(current_user)

    doc_ref, notification = get_notification_or_404(
        db,
        notification_id
    )

    verify_notification_owner(
        notification,
        user_id
    )

    doc_ref.delete()

    return {
        "message": "Notification deleted successfully.",
        "notificationID": notification_id
    }