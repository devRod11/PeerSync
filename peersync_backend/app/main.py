from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from app.database.firebase import initialize_firebase, get_firestore_client
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, projects, groups, milestones, tasks, submissions, announcements, notifications

app = FastAPI(
    title="PeerSync API",
    description="Backend API for PeerSync Mobile Application",
    version="1.0.0"
)

app.include_router(auth.router)
app.include_router(projects.router)
app.include_router(groups.router)
app.include_router(milestones.router)
app.include_router(tasks.router)
app.include_router(submissions.router)
app.include_router(announcements.router)
app.include_router(notifications.router)

# CORS configuration for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup_event():
    initialize_firebase()

@app.get("/")
async def root():
    return {
        "message": "Welcome to PeerSync API",
        "status": "Running"
    }


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "application": "PeerSync"
    }


# Temporary WebSocket echo endpoint for testing
@app.websocket("/ws/notifications")
async def notification_websocket(websocket: WebSocket):
    await websocket.accept()

    try:
        while True:
            message = await websocket.receive_text()

            await websocket.send_json({
                "type": "test",
                "message": message
            })

    except WebSocketDisconnect:
        print("WebSocket client disconnected.")


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
            "project": "peersync-11326"
        }

    except Exception as error:
        print(f"Firebase connection error: {error}")

        raise HTTPException(
            status_code=503,
            detail="Firebase connection failed."
        )
