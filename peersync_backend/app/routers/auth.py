from fastapi import APIRouter, Depends, HTTPException, status, Header
from pydantic import BaseModel, Field

from app.dependencies.auth import (
    get_current_user,
    require_professor,
    require_professor_identity,
    require_student,
)
from app.services.professor_session_service import (
    create_professor_session,
    revoke_professor_session,
)

from app.services.professor_otp_service import (issue_professor_otp, verify_professor_otp,)
from app.services.professor_session_service import (create_professor_session,)

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)


class ProfessorOTPVerifyRequest(BaseModel):
    code: str = Field(
        ...,
        min_length=6,
        max_length=6,
        pattern=r"^[0-9]{6}$"
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

@router.post("/professor/otp/request")
def request_professor_otp(
    current_user: dict = Depends(require_professor_identity)
):
    """
    Generate and send an OTP to the authenticated Professor.
    """

    email = current_user.get("email")

    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Professor email address is unavailable."
        )

    try:
        result = issue_professor_otp(
            uid=current_user["uid"],
            email=email
        )

        return result

    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(error)
        ) from None

    except RuntimeError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to send verification code. Please try again."
        ) from None

@router.post("/professor/otp/verify")
def verify_professor_otp_endpoint(
    request: ProfessorOTPVerifyRequest,
    current_user: dict = Depends(require_professor_identity)
):
    """
    Verify the Professor OTP and create a verified session.
    """

    try:
        verified = verify_professor_otp(
            uid=current_user["uid"],
            submitted_code=request.code
        )

        if not verified:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired verification code."
            )

        session = create_professor_session(
            uid=current_user["uid"]
        )

        return {
            "verified": True,
            "message": "Professor verification successful.",
            **session
        }

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to complete Professor verification."
        ) from None

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

@router.post("/professor/logout")
def professor_logout(
    current_user: dict = Depends(require_professor_identity),
    professor_session: str | None = Header(
        default=None,
        alias="X-Professor-OTP-Session"
    )
):
    """
    Revoke the current Professor OTP session.
    """

    if not professor_session:
        return {
            "success": True,
            "message": "No active Professor session."
        }

    try:
        revoked = revoke_professor_session(
            uid=current_user["uid"],
            session_token=professor_session
        )

        return {
            "success": True,
            "message": (
                "Professor session revoked."
                if revoked
                else "Professor session was already inactive."
            )
        }

    except Exception:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to revoke Professor session."
        ) from None