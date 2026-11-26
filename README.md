
# PeerSync

**PeerSync (PeerS): A Collaborative Milestone Tracking and Automated Notification Framework for Student Capstone Projects.**

PeerSync is a collaborative capstone project management platform designed to help professors supervise student groups and help students organize, track, and submit their project work.

The system consists of a Flutter application and a FastAPI backend integrated with Firebase. Professors can manage projects, groups, milestones, tasks, submissions, and announcements. Students can access their assigned projects, monitor deadlines, submit deliverables, receive feedback, and manage notifications.

PeerSync also integrates Google Calendar for deadline synchronization, Google Drive for submission file management, SendGrid for email delivery, and Firebase Cloud Messaging (FCM) for push notifications.

---

## Table of Contents

- [Feature Overview](#feature-overview)
- [Technology Stack](#technology-stack)
- [System Architecture](#system-architecture)
- [Repository Structure](#repository-structure)
- [Database Structure](#database-structure)
- [Authentication and Security](#authentication-and-security)
- [Integrations](#integrations)
- [Automated Email Digest](#automated-email-digest)
- [API and Deployment](#api-and-deployment)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Testing and Validation](#testing-and-validation)
- [Known Limitations](#known-limitations)
- [Development Guidelines](#development-guidelines)

---

## Feature Overview

### Professor Features

| Feature | Description |
|---|---|
| Dashboard | Overview of projects, student groups, activities, and progress. |
| Project Management | Create and manage capstone projects. |
| Group Management | Create groups, assign students, manage members, and designate Group Leaders. |
| Milestone Management | Create and organize project milestones. |
| Task Management | Create tasks, assign students, and monitor deadlines and completion. |
| Progress Monitoring | Monitor group and student progress across milestones and tasks. |
| Submission Review | Review student submissions, approve deliverables, or request revisions with feedback. |
| Announcements | Publish announcements to an entire project or selected groups. |
| Notifications | Receive in-app and push notifications about relevant activities. |
| Two-Factor Authentication | Verify professor login through a six-digit email OTP before accessing the dashboard. |

### Student Features

| Feature | Description |
|---|---|
| Dashboard | View assigned tasks, deadlines, and submission progress. |
| My Classes and Groups | View projects and groups the student belongs to. |
| Milestones and Tasks | Monitor assigned work and project deadlines. |
| Submissions | Upload deliverables through the Google Drive integration and resubmit when revisions are requested. |
| Feedback | View professor feedback and submission review status. |
| Announcements | Read announcements targeted to the student's project or group. |
| Notifications | Receive in-app and push notifications. |
| Google Calendar | Connect a personal Google account and synchronize assigned deadlines. |
| Profile and Settings | Manage account information and integration settings, including Calendar connection status. |

### Cross-Platform Features

- Flutter application supporting Android, web, Windows, macOS, Linux, and iOS targets, subject to platform-specific configuration.
- Responsive user interface for mobile and larger screens.
- Firebase Authentication for account authentication.
- Cloud Firestore for application data.
- Firebase Cloud Messaging for push notifications.
- Google Calendar API integration for student deadline synchronization.
- Google Drive API integration for submission file management.
- SendGrid email delivery for OTP verification and scheduled email digests.
- Offline read-data caching with a 72-hour time-to-live.
- Role-based access control for Professors and Students.

---

## Technology Stack

### Frontend

| Technology | Purpose |
|---|---|
| Flutter | Cross-platform application framework |
| Dart | Application programming language |
| Material 3 | User interface and design system |
| Firebase Authentication | User authentication |
| Firebase Core | Firebase initialization |
| Cloud Firestore | Firebase client integration |
| Firebase Cloud Messaging | Push notifications |
| HTTP | Backend API communication |
| Shared Preferences | Local preference and cache storage |
| URL Launcher | Opening external authorization and integration URLs |

### Backend

| Technology | Purpose |
|---|---|
| Python 3.11+ | Backend programming language |
| FastAPI | REST API framework |
| Uvicorn | ASGI server |
| Firebase Admin SDK | Firebase token verification and administration |
| Cloud Firestore | Database access |
| Pydantic | Request validation and settings |
| SendGrid | Email delivery |
| Google APIs | Calendar and Drive integrations |
| Ruff | Python linting and code quality |

### Cloud and Deployment

| Service | Purpose |
|---|---|
| Firebase Authentication | Account management |
| Cloud Firestore | Application database |
| Firebase Cloud Messaging | Push notification delivery |
| Render | FastAPI backend hosting |
| GitHub | Source code repository |
| GitHub Actions | Scheduled Email Digest processing |
| SendGrid | OTP and digest email delivery |
| Google Calendar API | Student deadline synchronization |
| Google Drive API | Submission file storage and management |

---

## System Architecture

PeerSync uses a Flutter frontend, a FastAPI backend, and Firebase services.

```text
                    PEERSYNC SYSTEM
                           |
             +-------------+-------------+
             |                           |
       FLUTTER CLIENT                FASTAPI BACKEND
       (Android / Web)               (Render Hosting)
             |                           |
             | HTTPS REST API             |
             +-------------------------->|
                                         |
                         +---------------+---------------+
                         |               |               |
                    Firebase Auth   Cloud Firestore   External APIs
                         |               |               |
                    User Login       Application Data   Google APIs
                    Professor OTP   Projects            SendGrid
                                    Groups
                                    Milestones
                                    Tasks
                                    Submissions
                                    Announcements
                                    Notifications
                                    Email Digest Records
                                         |
                                  Firebase Cloud
                                    Messaging
                                         |
                                  Push Notifications
```

### Authentication Flow

1. A user enters their email and password.
2. Firebase Authentication validates the credentials.
3. The Flutter application obtains a Firebase ID token.
4. The token is sent to the FastAPI backend through the Authorization Bearer header.
5. The backend verifies the token using Firebase Admin SDK.
6. The backend retrieves the user's Firestore profile.
7. Role and account-status checks determine which resources the user can access.
8. Professor accounts must complete email OTP verification before dashboard access.

### Authorization

Authorization is enforced by the backend rather than relying solely on frontend navigation visibility.

- Professors can manage their own projects and review student submissions.
- Students can access only the projects, groups, tasks, and submissions permitted by their membership and assignment.
- Inactive accounts are rejected.
- Group Leader is a student membership designation, not a separate system role.

---

## Repository Structure

```text
PeerSync/
|
├── README.md
|
├── .github/
│   └── workflows/
│       └── email-digest.yml
|
├── peersync_backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── core/
│   │   │   └── config.py
│   │   ├── database/
│   │   │   └── firebase.py
│   │   ├── dependencies/
│   │   │   └── auth.py
│   │   ├── routers/
│   │   │   ├── auth.py
│   │   │   ├── projects.py
│   │   │   ├── groups.py
│   │   │   ├── milestones.py
│   │   │   ├── tasks.py
│   │   │   ├── submissions.py
│   │   │   ├── announcements.py
│   │   │   ├── notifications.py
│   │   │   ├── google_calendar.py
│   │   │   ├── google_drive.py
│   │   │   └── email_digests.py
│   │   └── services/
│   │       ├── task_status_service.py
│   │       ├── notification_service.py
│   │       ├── push_service.py
│   │       ├── email_service.py
│   │       └── email_digest_service.py
│   ├── requirements.txt
│   └── pyproject.toml
|
└── peersync_mobile/
    ├── lib/
    │   ├── main.dart
    │   ├── firebase_options.dart
    │   ├── config/
    │   │   └── api_config.dart
    │   ├── core/
    │   │   ├── a11y/
    │   │   ├── cache/
    │   │   ├── push/
    │   │   ├── responsive/
    │   │   └── utils/
    │   ├── models/
    │   ├── pages/
    │   ├── services/
    │   ├── theme/
    │   └── widgets/
    ├── android/
    ├── ios/
    ├── web/
    ├── windows/
    ├── macos/
    ├── linux/
    └── pubspec.yaml
```

*Note: This is a logical overview of the main project structure. Additional files and folders may exist in the repository.*

---

## Database Structure

PeerSync uses Cloud Firestore as its primary database.

| Collection | Purpose |
|---|---|
| `users` | User profiles, roles, and account status. |
| `projects` | Capstone project information. |
| `groups` | Student groups associated with projects. |
| `group_members` | Student membership and Group Leader assignments. |
| `milestones` | Project milestone information and deadlines. |
| `tasks` | Tasks assigned to students or groups. |
| `submissions` | Submission records, Google Drive references, and review information. |
| `announcements` | Professor announcements and target audiences. |
| `notifications` | In-app notification records. |
| `device_tokens` | Registered FCM device tokens. |
| `email_digests` | Per-recipient digest scheduling and processing information. |

### Important Data Rules

- Firebase UID is used as the document ID for user profiles.
- Firestore field names follow the established camelCase naming convention unless an existing field intentionally differs.
- `notifications.Title` retains its existing uppercase `T`; do not rename it without a coordinated data migration.
- Group membership is represented through `group_members`.
- A Group Leader remains a Student account.
- Submission records reference files stored through the Google Drive integration.
- Email digest tracking is maintained separately from ordinary notification records.

---

## Authentication and Security

### Firebase Authentication

PeerSync uses Firebase Authentication with email and password credentials.

The backend verifies Firebase ID tokens before allowing access to protected API endpoints.

### Professor Email OTP

Professor accounts require an additional email verification step after successful credential validation.

The OTP implementation includes:

- Six-digit email verification codes.
- SendGrid email delivery.
- 60-second resend cooldown.
- 15-minute OTP expiration configured for development and testing.
- Maximum of five verification attempts.
- HMAC-based OTP hash storage in Firestore.
- Professor session token storage in Flutter secure storage.
- Professor dashboard access only after successful OTP verification.

Professor OTP verification is separate from the scheduled Email Digest system.

### Backend Authorization

The backend performs role and account-status checks on protected endpoints.

Important security practices:

- Do not expose Firebase service account credentials in the Flutter application.
- Do not commit `.env` files or secret credentials.
- Store production secrets in Render environment variables or appropriate secret-file configuration.
- Keep Google OAuth client secrets on the backend.
- Protect internal scheduler endpoints using a dedicated secret header.
- Validate ownership and membership before allowing access to project-related data.

---

## Integrations

### Google Calendar Integration

PeerSync allows students to connect their individual Google accounts to synchronize assigned task and milestone deadlines.

Features include:

- Individual student Google OAuth authorization.
- Connect and disconnect controls in Profile and Settings.
- Calendar connection-status checking.
- Synchronization of assigned task and milestone deadlines.
- Student-controlled Google account authorization.
- Professor accounts do not display the student-only Calendar connection section.

Students can connect their Google accounts when convenient. Calendar connection is not required to use the main application.

### Google Drive Integration

Google Drive is used to manage student submission files.

The integration supports:

- Google OAuth authorization through the backend.
- Uploading submission files to the configured Google Drive folder.
- Recording Drive file references in Firestore.
- Professor review of submitted work.
- Approval and revision-request workflows.
- Student resubmission after a revision request.

The backend handles Google Drive API communication so that sensitive OAuth credentials are not exposed in the Flutter client.

### Firebase Cloud Messaging

FCM provides push notifications for Android and Chrome Web.

The application supports:

- Device-token registration.
- Foreground notification handling.
- Background notification delivery.
- Terminated-app notification delivery.
- Backend-triggered push notifications.
- Token registration and removal.
- In-app notification records as the primary notification history.

Push delivery is supplementary to the in-app notification system.

### SendGrid Email Service

SendGrid is used for transactional and automated email delivery.

Current uses include:

- Professor OTP verification emails.
- Professor OTP resend requests.
- Scheduled notification digest emails.

OTP emails remain immediate and are not included in the scheduled digest process.

---

## Automated Email Digest

PeerSync includes an automated email digest feature designed to reduce the frequency of notification emails while keeping users informed about relevant activity.

### Digest Behavior

- Email digest interval: 72 hours.
- The scheduler checks for due digests hourly.
- Due notifications are retrieved from Firestore.
- Digest emails are delivered using SendGrid.
- Digest tracking records are maintained in Firestore.
- Failed processing can be retried by subsequent scheduler executions.
- Immediate in-app notifications and FCM push notifications remain unchanged.
- Professor OTP emails are sent immediately and are independent of digest scheduling.

### Scheduler Architecture

GitHub Actions is used as the scheduled trigger for the deployed FastAPI backend.

Workflow file:

```text
.github/workflows/email-digest.yml
```

Schedule:

```yaml
schedule:
  - cron: "0 * * * *"
```

The workflow sends a protected POST request to:

```text
POST /internal/email-digests/process
```

The endpoint requires the following HTTP header:

```text
X-Email-Digest-Secret
```

The scheduler uses two GitHub Repository Actions secrets:

| Secret | Purpose |
|---|---|
| `PEERSYNC_API_URL` | Base URL of the deployed PeerSync backend. |
| `EMAIL_DIGEST_CRON_SECRET` | Secret used to authenticate the scheduler request. |

The workflow removes a trailing slash from the backend base URL before appending the endpoint path.

Example command:

```bash
curl --fail --silent --show-error \
  --request POST \
  "${PEERSYNC_API_URL%/}/internal/email-digests/process" \
  --header "X-Email-Digest-Secret: ${EMAIL_DIGEST_CRON_SECRET}"
```

The scheduler can also be triggered manually through:

**GitHub → Actions → PeerSync Email Digest → Run workflow**

### Email Digest Validation

The following have been verified:

- GitHub Actions successfully triggers the backend endpoint.
- Render accepts the authenticated scheduler request.
- The backend processes Firestore digest records.
- SendGrid email delivery has been functionally tested.
- The user has confirmed that the Email Digest feature is working.

---

## API and Deployment

### Deployed Backend

PeerSync's FastAPI backend is deployed through Render.

Backend base URL:

```text
https://peersync-backend-hi1u.onrender.com
```

Interactive API documentation:

```text
https://peersync-backend-hi1u.onrender.com/docs
```

The API is consumed by the Flutter application through HTTPS.

### API Base URL Configuration

The Flutter application uses:

```text
peersync_mobile/lib/config/api_config.dart
```

The `ApiConfig` class supports platform-specific defaults and a compile-time override through:

```text
PEERSYNC_API_BASE_URL
```

Default local development URLs:

| Platform | Default URL |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| Chrome / Web | `http://localhost:8000` |
| iOS simulator | `http://localhost:8000` |
| Desktop | `http://localhost:8000` |

To run the application using the deployed Render backend:

```powershell
flutter run --dart-define=PEERSYNC_API_BASE_URL=https://peersync-backend-hi1u.onrender.com
```

To build the web application using Render:

```powershell
flutter build web --dart-define=PEERSYNC_API_BASE_URL=https://peersync-backend-hi1u.onrender.com
```

The web build has successfully completed using this configuration.

### Backend Deployment Notes

The backend requires its Firebase service account configuration and integration credentials to be configured securely in Render.

Do not place production credentials in the Flutter application or commit them to GitHub.

---

## Getting Started

### Prerequisites

- Flutter SDK with a compatible Dart SDK.
- Python 3.11 or later.
- Git.
- Android Studio or an Android emulator for Android development.
- Chrome for web development.
- A configured Firebase project.
- Firebase Authentication, Cloud Firestore, and Firebase Cloud Messaging enabled.

### 1. Clone the Repository

```bash
git clone https://github.com/devRod11/PeerSync.git
cd PeerSync
```

### 2. Backend Setup

Navigate to the backend:

```powershell
cd peersync_backend
```

Create a virtual environment:

```powershell
python -m venv .venv
```

Activate it on Windows:

```powershell
.venv\Scripts\Activate.ps1
```

Install dependencies:

```powershell
pip install -r requirements.txt
```

Configure the backend environment variables and Firebase service account credentials before running the server.

Start the backend:

```powershell
uvicorn app.main:app --reload --port 8000
```

Local API documentation:

```text
http://localhost:8000/docs
```

### 3. Flutter Setup

Open another terminal and navigate to the Flutter application:

```powershell
cd peersync_mobile
```

Install Flutter dependencies:

```powershell
flutter pub get
```

Check available devices:

```powershell
flutter devices
```

Run the application using the local backend:

```powershell
flutter run
```

Run the application using the deployed Render backend:

```powershell
flutter run --dart-define=PEERSYNC_API_BASE_URL=https://peersync-backend-hi1u.onrender.com
```

### 4. Run on Chrome

```powershell
flutter run -d chrome --dart-define=PEERSYNC_API_BASE_URL=https://peersync-backend-hi1u.onrender.com
```

### 5. Build the Web Application

```powershell
flutter build web --dart-define=PEERSYNC_API_BASE_URL=https://peersync-backend-hi1u.onrender.com
```

The compiled web application is generated in:

```text
peersync_mobile/build/web/
```

---

## Configuration

### Flutter Compile-Time Configuration

| Variable | Purpose |
|---|---|
| `PEERSYNC_API_BASE_URL` | Overrides the default backend API URL. |
| `PEERSYNC_WEB_VAPID_KEY` | Firebase Web Push VAPID key for web push notifications. |

Example:

```powershell
flutter run --dart-define=PEERSYNC_API_BASE_URL=https://peersync-backend-hi1u.onrender.com
```

### Backend Configuration

The backend uses environment-based configuration through Pydantic Settings.

The deployed environment requires the appropriate configuration for:

- Firebase project and service account credentials.
- CORS allowed origins.
- SendGrid email delivery.
- Professor OTP verification.
- Google OAuth and Calendar integration.
- Google Drive integration.
- Email Digest scheduler authentication.

The scheduler secret must be configured as:

```text
EMAIL_DIGEST_CRON_SECRET
```

The same secret value must be configured in the Render backend environment and the GitHub repository's Actions secrets.

Never commit actual secret values to the repository.

---

## Testing and Validation

The following table summarizes the integration and functional validation reported during development.

| Component | Validation | Status |
|---|---|---|
| Firebase Authentication | Student and Professor credential validation | Tested |
| Role Validation | Account-role mismatch and inactive-account rejection | Tested |
| Professor OTP | Request, resend, expiration, and verification flow | Tested |
| Google Drive | Upload, review, approval, revision, and resubmission workflow | Tested |
| Google Calendar | Student authorization, status, synchronization, and disconnect | Tested |
| FCM Android | Token registration and foreground, background, terminated, and backend-triggered delivery | Tested |
| FCM Chrome Web | Web push notification delivery | Tested |
| Email Digest | GitHub Actions scheduler, backend authentication, Firestore processing, and SendGrid delivery | Tested |
| Render Backend | Deployed API and Swagger documentation access | Tested |
| Flutter Web | Production API URL configuration and successful web compilation | Tested |

### Static and Automated Checks

Backend:

```powershell
cd peersync_backend
ruff check app
python -m compileall app
```

Flutter:

```powershell
cd peersync_mobile
flutter analyze
flutter test
```

### Recommended Regression Tests

Before a release, continue testing:

- Professor and Student access restrictions.
- Project and group membership validation.
- Milestone and task assignment.
- Submission approval and revision workflows.
- Google Drive authorization and file access.
- Google Calendar synchronization and disconnection.
- Professor OTP resend and expiration behavior.
- FCM delivery on supported platforms.
- Email Digest scheduling, retries, and recipient targeting.
- Offline cache behavior and account isolation.
- API authorization and validation errors.

Functional integration tests should be distinguished from automated unit and regression tests. A manually verified integration does not automatically mean that a permanent automated test has been added.

---

## Accessibility

PeerSync uses the Material 3 design system and aims to follow WCAG 2.2 Level AA accessibility principles.

The application uses the following brand colors:

| Color | Hex |
|---|---|
| Primary Navy | `#0A2342` |
| Background | `#F2F5FF` |

Accessibility considerations include:

- Readable text and sufficient color contrast.
- Clear status labels and visual indicators.
- Accessible labels for interactive controls.
- Keyboard navigation support where applicable.
- Appropriate touch-target sizing.
- Responsive layouts and text scaling.
- Reduced-motion considerations.

Formal accessibility certification has not been claimed.

---

## Offline Support

PeerSync includes a local read-data cache with a 72-hour time-to-live.

The intended behavior is network-first with cache fallback:

1. The application attempts to retrieve data from the backend.
2. Successful responses are cached locally.
3. If a network failure occurs, valid cached data may be displayed.
4. Expired cache entries are not treated as current data.
5. Authentication and authorization errors are not hidden by stale cached responses.

Offline caching does not mean that all application operations are available without an internet connection. Operations that require backend communication still need connectivity.

---

## Known Limitations

- Professor OTP email delivery depends on third-party email delivery and sender-domain configuration. Gmail delivery may occasionally be delayed.
- Google Calendar synchronization requires the student to authorize their own Google account.
- Google Drive and Calendar integrations depend on valid Google OAuth configuration and API availability.
- Push notifications depend on Firebase Cloud Messaging and device/browser permissions.
- The Flutter Web build has been successfully compiled, but this does not constitute full validation of every browser and deployment environment.
- iOS and desktop platform-specific configurations may require additional setup and testing.
- Offline caching is intended for supported read operations and does not provide complete offline application functionality.
- Automated unit and regression test coverage should continue to be expanded.
- Email Digest processing depends on GitHub Actions availability and the deployed backend being reachable.
- Email delivery and push notification delivery are separate channels with different delivery behavior.

---

## Development Guidelines

### Branching

Use feature branches for development and merge completed changes into `main` through pull requests.

Avoid committing experimental or incomplete changes directly to `main.

### Code and Data Conventions

- Preserve existing Firestore collection names and field names.
- Maintain compatibility between Flutter models and backend schemas.
- Enforce authorization on the backend.
- Keep Professor-only functionality separate from Student-only functionality.
- Keep Professor OTP verification separate from scheduled Email Digest delivery.
- Keep Google OAuth credentials and service account credentials on the backend.
- Do not commit `.env` files, private keys, service account JSON files, or API secrets.
- Update this README when major features, integrations, or deployment procedures change.

### Before Merging Changes

Run the relevant checks:

```powershell
cd peersync_backend
ruff check app
python -m compileall app
```

```powershell
cd peersync_mobile
flutter analyze
flutter test
```

---

## License

No license file is currently included in this repository. All rights are reserved unless a license is added.
