import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.database.firebase import get_firestore_client, initialize_firebase
from app.routers import (
    announcements,
    auth,
    groups,
    milestones,
    notifications,
    projects,
    submissions,
    tasks,
    google_drive,
    google_calendar
)


logger = logging.getLogger("peersync")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Initialise shared resources once, before the app starts serving."""
    initialize_firebase()
    logger.info("PeerSync API started.")
    yield
    logger.info("PeerSync API stopped.")


app = FastAPI(
    title="PeerSync API",
    description="Backend API for PeerSync Mobile Application",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(auth.router)
app.include_router(projects.router)
app.include_router(groups.router)
app.include_router(milestones.router)
app.include_router(tasks.router)
app.include_router(submissions.router)
app.include_router(announcements.router)
app.include_router(notifications.router)
app.include_router(google_drive.router)
app.include_router(google_calendar.router)

# CORS: the allowed origins are configurable through the CORS_ALLOW_ORIGINS
# environment variable (comma separated). The default keeps the previous
# permissive behaviour so existing deployments are not broken.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"message": "Welcome to PeerSync API", "status": "Running"}


@app.get("/health")
async def health_check():
    return {"status": "healthy", "application": "PeerSync"}


@app.get("/health/firebase")
async def firebase_health_check():
    try:
        db = get_firestore_client()

        # Perform a small read operation against Firestore.
        db.collection("users").limit(1).get()

        return {
            "status": "connected",
            "application": "PeerSync",
            "database": "Cloud Firestore",
            "project": settings.firebase_project_id,
        }

    except Exception:
        # Log the full stack trace server-side, but never leak it to clients.
        logger.exception("Firebase connectivity check failed.")

        raise HTTPException(
            status_code=503,
            detail="Firebase connection failed.",
        ) from None
