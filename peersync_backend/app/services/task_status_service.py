from datetime import datetime, timezone

def get_submission_timestamp(submission: dict) -> float:
    """
    Convert submittedAt into a comparable timestamp.
    Supports older records with the misspelled subittedAt field.
    """
    submitted_at = submission.get(
        "submittedAt",
        submission.get("subittedAt")
    )

    if not isinstance(submitted_at, datetime):
        return 0.0

    if submitted_at.tzinfo is None:
        submitted_at = submitted_at.replace(tzinfo=timezone.utc)

    return submitted_at.timestamp()


def recalculate_task_status(db, task_id: str):
    """
    Recalculate task status using the latest submission
    of each currently assigned student.
    """

    task_ref = db.collection("tasks").document(task_id)
    task_doc = task_ref.get()

    if not task_doc.exists:
        return None

    task = task_doc.to_dict()
    assigned_students = task.get("assignedTo", [])

    # Retrieve all submissions belonging to this task.
    submission_docs = (
        db.collection("submissions")
        .where("taskID", "==", task_id)
        .stream()
    )

    # Keep only the latest submission for each assigned student.
    latest_submissions = {}

    for doc in submission_docs:
        submission = doc.to_dict()
        student_id = submission.get("submittedBy")

        # Ignore submissions from students no longer assigned.
        if student_id not in assigned_students:
            continue

        timestamp = get_submission_timestamp(submission)

        # Use document ID as a tie-breaker for equal timestamps.
        sort_key = (timestamp, doc.id)

        previous = latest_submissions.get(student_id)

        if previous is None or sort_key > previous["sortKey"]:
            latest_submissions[student_id] = {
                "status": submission.get("status"),
                "sortKey": sort_key
            }

    # Determine the new task status.
    if not assigned_students:
        new_status = "pending"

    elif not latest_submissions:
        new_status = "pending"

    elif all(
        student_id in latest_submissions
        and latest_submissions[student_id]["status"] == "approved"
        for student_id in assigned_students
    ):
        new_status = "completed"

    else:
        new_status = "in_progress"

    # Update Firestore only when the status actually changes.
    if task.get("status") != new_status:
        task_ref.update({
            "status": new_status,
            "updatedAt": datetime.now(timezone.utc)
        })

    return new_status