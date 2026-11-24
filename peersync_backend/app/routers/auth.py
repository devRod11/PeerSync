from fastapi import APIRouter, Depends

from app.dependencies.auth import get_current_user, require_professor, require_student

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)


@router.get("/me")
def get_authenticated_user(
    current_user: dict = Depends(get_current_user)
):
    """
    Return the currently authenticated user's profile.
    """

    return {
        "authenticated": True,
        "user": current_user
    }


@router.get("/professor-check")
def professor_access_test(
    current_user: dict = Depends(require_professor)
):
    """
    Temporary endpoint for testing Professor authorization.
    """

    return {
        "message": "Professor access granted.",
        "uid": current_user["uid"],
        "role": current_user["role"]
    }


@router.get("/student-check")
def student_access_test(
    current_user: dict = Depends(require_student)
):
    """
    Temporary endpoint for testing Student authorization.
    """

    return {
        "message": "Student access granted.",
        "uid": current_user["uid"],
        "role": current_user["role"]
    }
