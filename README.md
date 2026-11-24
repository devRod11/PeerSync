# PeerSync

**A capstone project collaboration platform for professors and students.**

PeerSync is a two-part system: a Flutter application that runs on Android, iOS, web, Windows, macOS and Linux, and a FastAPI backend that sits in front of Firebase Authentication and Cloud Firestore. Professors create projects, divide them into milestones, form student groups and review submitted work. Students see only the projects they belong to, track their milestones and tasks, submit deliverables, and receive feedback and announcements.

The app is designed for the way capstone courses actually run: one professor supervising several projects, each project split into groups, each group working through an ordered sequence of milestones, and each milestone broken into assigned tasks that students submit against and professors review.

* * *

## Table of contents

-   [Feature overview](#feature-overview)
-   [Architecture](#architecture)
-   [Technology stack](#technology-stack)
-   [Repository layout](#repository-layout)
-   [Data model](#data-model)
-   [Roles and permissions](#roles-and-permissions)
-   [Business rules](#business-rules)
-   [API reference](#api-reference)
-   [Getting started](#getting-started)
    -   [Prerequisites](#prerequisites)
    -   [Backend setup](#backend-setup)
    -   [Mobile setup](#mobile-setup)
    -   [Web / PWA setup](#web--pwa-setup)
-   [Configuration reference](#configuration-reference)
-   [Accessibility](#accessibility)
-   [Offline support](#offline-support)
-   [Push notifications](#push-notifications)
-   [Testing](#testing)
-   [Troubleshooting](#troubleshooting)
-   [Known limitations](#known-limitations)
-   [Contributing](#contributing)

* * *

## Feature overview

### For professors

| Area | What it does |
| --- | --- |
| **Dashboard** | Landing view with an overview of the professor's own projects and current activity. |
| **Classes** | Create and manage projects, then create groups inside them. Assign students to groups and designate a Group Leader. |
| **Group management** | Add or remove members, reassign leadership, and inspect a group's roster and progress. |
| **Progress** | Milestones and tasks per project. Create ordered milestones, break them into tasks, assign tasks to specific students, and monitor completion. |
| **Review** | Review submitted work, approve it, or request a revision with written feedback. |
| **Updates** | Publish announcements to a whole project or to specific groups only. |
| **Notifications** | In-app notification list with read/unread state and a badge count. |
| **Profile** | Account details and sign-out. |

### For students

| Area | What it does |
| --- | --- |
| **Dashboard** | Personal view of assigned tasks, upcoming deadlines and submission status. |
| **My Classes** | The projects and groups the student actually belongs to. |
| **Activities** | Tasks assigned to the student, with the ability to submit deliverables and resubmit after a revision request. |
| **Updates** | Announcements targeted at their project or their group. |
| **Notifications** | Same in-app notification list, scoped to the student. |
| **Profile** | Account details and sign-out. |

### Cross-cutting

-   **Responsive layout** — bottom navigation on phones, a `NavigationRail` on tablets and desktops, with content width capped for readability.
-   **Installable PWA** — web build ships a manifest, maskable icons, a boot splash and a service worker.
-   **Push notifications** — Firebase Cloud Messaging on Android, iOS and web, layered on top of the in-app notification list.
-   **Offline support** — core read data is cached locally for 72 hours so the app stays usable without a connection.
-   **Accessibility** — WCAG 2.2 Level AA target across contrast, semantics, keyboard access, focus management, tap targets and reduced motion.

* * *

## Architecture

```
┌──────────────────────────────────────────┐
│  Flutter app (peersync_mobile)           │
│                                          │
│  main.dart                               │
│    └─ AuthGate  ── Firebase Auth session │
│         └─ PeerSyncShell                 │
│              ├─ Professor pages          │
│              └─ Student pages            │
│                                          │
│  services/api_service.dart               │
│    ├─ Firebase ID token → Bearer header  │
│    ├─ network-first request              │
│    └─ offline cache fallback             │
└───────────────┬──────────────────────────┘
                │  HTTPS + JSON
                ▼
┌──────────────────────────────────────────┐
│  FastAPI backend (peersync_backend)      │
│                                          │
│  dependencies/auth.py                    │
│    ├─ verify Firebase ID token           │
│    ├─ load users/{uid} profile           │
│    └─ require_professor / require_student│
│                                          │
│  routers/  (projects, groups, milestones,│
│             tasks, submissions,          │
│             announcements, notifications)│
│                                          │
│  services/                               │
│    ├─ task_status_service  (recalculate) │
│    ├─ notification_service (in-app rows) │
│    └─ push_service         (FCM delivery)│
└───────────────┬──────────────────────────┘
                │  Firebase Admin SDK
                ▼
┌──────────────────────────────────────────┐
│  Firebase                                │
│    ├─ Authentication (email / password)  │
│    ├─ Cloud Firestore (all app data)     │
│    └─ Cloud Messaging (push delivery)    │
└──────────────────────────────────────────┘
```

Two properties of this design matter more than the rest:

**Authentication is delegated, authorisation is enforced server-side.** The client never talks to Firestore directly for application data. It authenticates with Firebase Auth, obtains an ID token, and sends that token to FastAPI on every request. FastAPI verifies the token with the Admin SDK (`check_revoked=True`), loads the caller's `users/{uid}` document, and applies role checks per route. This means Firestore security rules do not have to carry the whole authorisation burden, and role logic lives in one place.

**Notifications have one source of truth and one optional extra channel.** Every notification is written to the `notifications` collection first. Push delivery is attempted afterwards and is strictly best-effort — a missing credential, an expired token or a network failure never fails the request that triggered it. If push is unavailable, the in-app list still works.

* * *

## Technology stack

### Mobile / web client

| Concern | Choice |
| --- | --- |
| Framework | Flutter, Dart SDK `^3.13.7` |
| Design system | Material 3 (`useMaterial3: true`) |
| Auth | `firebase_auth ^7.0.1` |
| Push | `firebase_messaging ^17.1.0` |
| Firebase core | `firebase_core ^5.2.0` |
| Firestore client | `cloud_firestore ^7.1.0` |
| Local storage | `shared_preferences ^2.5.6` |
| HTTP | `http ^1.6.0` |
| Lints | `flutter_lints ^6.0.0` |

### Backend

| Concern | Choice |
| --- | --- |
| Framework | FastAPI `0.162.0` |
| Server | Uvicorn `0.54.0` |
| Validation | Pydantic `2.14.2` + `pydantic-settings` |
| Firebase | `firebase_admin 7.7.0` |
| Firestore | `google-cloud-firestore 2.34.1` |
| Static analysis | Ruff (`E`, `F`, `I`, `B`, `SIM`; line length 100) |
| Python | 3.11 |

* * *

## Repository layout

```
PeerSync/
├── README.md
├── peersync_backend/
│   ├── app/
│   │   ├── main.py                     # FastAPI app, CORS, health endpoints
│   │   ├── core/
│   │   │   └── config.py               # Settings (env-driven)
│   │   ├── database/
│   │   │   └── firebase.py             # Admin SDK + Firestore client singletons
│   │   ├── dependencies/
│   │   │   └── auth.py                 # get_current_user, require_professor/student
│   │   ├── routers/
│   │   │   ├── auth.py                 # /auth
│   │   │   ├── projects.py             # /projects
│   │   │   ├── groups.py               # /groups
│   │   │   ├── milestones.py           # /milestones
│   │   │   ├── tasks.py                # /tasks
│   │   │   ├── submissions.py          # /submissions
│   │   │   ├── announcements.py        # /announcements
│   │   │   └── notifications.py        # /notifications
│   │   ├── schemas/                    # placeholder package (models live in routers)
│   │   └── services/
│   │       ├── task_status_service.py  # automatic task status recalculation
│   │       ├── notification_service.py # in-app notification creation
│   │       └── push_service.py         # FCM multicast delivery
│   ├── pyproject.toml                  # Ruff configuration
│   └── requirements.txt                # pinned dependencies
│
└── peersync_mobile/
    ├── lib/
    │   ├── main.dart                   # app entry, AuthGate, navigation shell
    │   ├── firebase_options.dart       # generated Firebase config
    │   ├── config/
    │   │   └── api_config.dart         # platform-aware API base URL
    │   ├── core/
    │   │   ├── a11y/                   # semantics, announcements, status wording
    │   │   ├── cache/offline_cache.dart# 72-hour TTL cache
    │   │   ├── push/                   # FCM service
    │   │   ├── responsive/             # breakpoints, window size classes
    │   │   └── utils/error_messages.dart
    │   ├── models/                     # plain Dart data classes
    │   ├── pages/                      # one file per screen
    │   ├── services/api_service.dart   # typed API client
    │   ├── theme/                      # colours and ThemeData
    │   └── widgets/                    # shared UI primitives
    ├── test/widget_test.dart
    ├── web/                            # PWA shell, manifest, service worker
    ├── android/  ios/  macos/  windows/  linux/
    ├── firebase.json
    ├── analysis_options.yaml
    └── pubspec.yaml
```

* * *

## Data model

All application data lives in Cloud Firestore. Field names are camelCase and are treated as a stable contract — the Dart models and the Pydantic schemas both depend on them.

| Collection | Purpose | Notable fields |
| --- | --- | --- |
| `users` | One document per account, keyed by Firebase UID. | `role` (`Professor` / `Student`), `displayName`, `email`, `isActive` |
| `projects` | A capstone project owned by a professor. | `title`, `description`, `academicYear`, `status`, `professorID` |
| `groups` | A team inside a project. | `groupName`, `projectID`, `professorID`, `leaderID` |
| `group_members` | Join documents linking students to groups. | `groupID`, `studentID`, `memberRole` (`Leader` / `Member`), `joinedAt` |
| `milestones` | Ordered phases of a project. | `projectID`, `groupID[]`, `title`, `sequence`, `startDate`, `dueDate`, `status` |
| `tasks` | Work items inside a milestone. | `projectID`, `groupID`, `milestoneID`, `assignedTo[]`, `priority`, `status`, `createdBy`, `createdByRole` |
| `submissions` | A student's deliverable for a task. | `taskID`, `groupID`, `submittedBy`, `fileName`, `fileType`, `driveFileId`, `status`, `feedback`, `reviewedBy` |
| `announcements` | Professor-authored notices. | `projectID`, `authorID`, `targetType` (`project` / `group`), `groupID[]`, `title`, `content` |
| `notifications` | Per-recipient in-app notifications. | `recipientID`, `Title`, `description`, `type`, `isRead`, `relatedCollections`, `relatedDocumentID` |
| `device_tokens` | FCM registration tokens. | `userID`, `token`, `platform`, `createdAt`, `updatedAt` |

A note on `notifications.Title`: the capital `T` is intentional and load-bearing. It is the existing field name in the deployed data, and both the backend and `lib/models/notification.dart` read it as written. Do not "fix" the casing without a data migration.

`device_tokens` documents use `sha256(token)` as their document ID, which makes registration idempotent — re-registering the same device updates one document instead of creating duplicates.

* * *

## Roles and permissions

There are exactly two roles, stored as `users/{uid}.role`.

| Capability | Professor | Student |
| --- | :-: | :-: |
| Create / edit / delete projects | ✅ | ❌ |
| Create / edit / delete groups and members | ✅ | ❌ |
| Assign a Group Leader | ✅ | ❌ |
| Create / edit / delete milestones | ✅ | ❌ |
| Create / edit / delete tasks | ✅ | ❌ |
| Review submissions (approve / request revision) | ✅ | ❌ |
| Publish announcements | ✅ | ❌ |
| View all projects they own | ✅ | ❌ |
| View projects and groups they belong to | ❌ | ✅ |
| View their own submissions | ❌ | ✅ |
| Submit / resubmit work | ❌ | ✅ |
| Read announcements targeted at them | ✅ (own) | ✅ |
| Read and manage own notifications | ✅ | ✅ |

**Group Leader is not a role.** It is a `memberRole` value on a `group_members` document. A Group Leader is still a Student with exactly the same API permissions; leadership is a label used for display and for deciding who is expected to coordinate the group. It must never be used as an authorisation check.

Inactive accounts (`isActive: false`) are rejected at the auth gate before any role logic runs.

* * *

## Business rules

These are the invariants the backend enforces. They are the parts most likely to break under refactoring, so they are listed explicitly.

**Submissions follow a strict state machine.** A submission starts as `pending`. A professor moves it to `approved` or `revision_required` — those are the only two accepted review statuses. Only `pending` submissions can be reviewed or deleted. A student may not create a new submission for a task while their previous one is still `pending` (the API returns a conflict with "Your previous submission is still pending review"). Once a task is `approved`, further submissions are rejected. Resubmission is only permitted after `revision_required`.

**Task status is derived, never set by hand.** `task_status_service.recalculate_task_status` computes a task's status from the latest submission of each currently assigned student. It ignores submissions from students who are no longer assigned, and uses the document ID as a tie-breaker when two submissions share a timestamp. The service also tolerates legacy records that used the misspelled `subittedAt` field. Clients must not offer a manual task-status control.

**Review actions live in Progress Monitoring, not Activities.** Professors review from the Progress screen. The student-facing Activities screen is where submission and resubmission happen. Keeping these separate is deliberate: it prevents the same action appearing in two places with two different permission checks.

**Announcement audience is computed once and reused.** `targetType: project` reaches every student in the project and requires `groupID` to be null. `targetType: group` requires at least one `groupID`. The recipient list is derived from `group_members` membership. The same recipient computation feeds both in-app notification creation and push delivery, so the push audience can never drift from the in-app audience. Professors do not receive notifications for announcements they authored.

**Milestone status is shared, not per-group.** A milestone's `status` describes the milestone itself. It must not be presented as "this group has completed this milestone" — group completion is a separate, derived notion.

**Group membership is validated before it is written.** A designated `leaderID` must appear in the member list, and every member ID must resolve to an existing Student account.

* * *

## API reference

Base URL in development: `http://localhost:8000`. Interactive docs are served by FastAPI at `/docs` and `/redoc`.

All endpoints except `/`, `/health`, `/health/firebase` require an `Authorization: Bearer <firebase-id-token>` header.

### System

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/` | Welcome payload. |
| `GET` | `/health` | Liveness check. |
| `GET` | `/health/firebase` | Verifies Firestore connectivity; returns `503` on failure. |

### Authentication — `/auth`

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/auth/me` | Returns the authenticated user's profile. |
| `GET` | `/auth/professor-check` | Professor-only access probe. |
| `GET` | `/auth/student-check` | Student-only access probe. |

### Projects — `/projects`

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/projects/` | Create a project (professor). |
| `GET` | `/projects/` | List projects visible to the caller. |
| `GET` | `/projects/{project_id}` | Project detail. |
| `PUT` | `/projects/{project_id}` | Update a project. |
| `DELETE` | `/projects/{project_id}` | Delete a project. |

### Groups — `/groups`

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/groups/` | Create a group. |
| `GET` | `/groups/` | List groups visible to the caller. |
| `GET` | `/groups/available-students` | Students eligible to be added. |
| `GET` | `/groups/{group_id}` | Group detail with roster. |
| `PUT` | `/groups/{group_id}` | Update group metadata. |
| `POST` | `/groups/{group_id}/members` | Add members. |
| `PUT` | `/groups/{group_id}/leader` | Assign the Group Leader. |
| `DELETE` | `/groups/{group_id}/members/{student_id}` | Remove a member. |
| `DELETE` | `/groups/{group_id}` | Delete a group. |

### Milestones — `/milestones`

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/milestones/` | Create a milestone. |
| `GET` | `/milestones/` | List milestones (filterable by project / group). |
| `GET` | `/milestones/{milestone_id}` | Milestone detail. |
| `PUT` | `/milestones/{milestone_id}` | Update a milestone. |
| `DELETE` | `/milestones/{milestone_id}` | Delete a milestone. |

### Tasks — `/tasks`

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/tasks/` | Create a task and notify assignees. |
| `GET` | `/tasks/` | List tasks (filterable by project / group / milestone / assignee). |
| `GET` | `/tasks/{task_id}` | Task detail. |
| `PUT` | `/tasks/{task_id}` | Update a task; reassignment re-notifies. |
| `DELETE` | `/tasks/{task_id}` | Delete a task. |

### Submissions — `/submissions`

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/submissions/` | Submit work for a task (student). |
| `GET` | `/submissions/` | List submissions visible to the caller. |
| `GET` | `/submissions/{submission_id}` | Submission detail. |
| `PATCH` | `/submissions/{submission_id}/review` | Approve or request revision (professor). |
| `DELETE` | `/submissions/{submission_id}` | Delete a pending submission. |

### Announcements — `/announcements`

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/announcements/` | Publish an announcement and notify recipients. |
| `GET` | `/announcements/` | List announcements visible to the caller. |
| `GET` | `/announcements/{announcement_id}` | Announcement detail. |
| `PUT` | `/announcements/{announcement_id}` | Update an announcement. |
| `DELETE` | `/announcements/{announcement_id}` | Delete an announcement. |

### Notifications — `/notifications`

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/notifications/` | List the caller's notifications. |
| `POST` | `/notifications/devices` | Register an FCM token for the caller. |
| `DELETE` | `/notifications/devices/{token}` | Unregister a token (owner only; `403` otherwise). |
| `GET` | `/notifications/{notification_id}` | Notification detail. |
| `PATCH` | `/notifications/read-all` | Mark all as read. |
| `PATCH` | `/notifications/{notification_id}` | Update read state. |
| `DELETE` | `/notifications/{notification_id}` | Delete a notification. |

* * *

## Getting started

### Prerequisites

-   **Flutter SDK** with Dart `>= 3.13.7` (`flutter --version`)
-   **Python 3.11+**
-   **A Firebase project** with Authentication (email/password), Cloud Firestore and Cloud Messaging enabled
-   **A Firebase service account key** (JSON) for the backend
-   **Chrome** for web development (optional)

### Backend setup

```bash
cd peersync_backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Create `peersync_backend/.env`:

```dotenv
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CREDENTIALS_PATH=serviceAccountKey.json
CORS_ALLOW_ORIGINS=*
```

`FIREBASE_CREDENTIALS_PATH` may be absolute or relative to `peersync_backend/`. Place the service account JSON accordingly and never commit it.

Run the API:

```bash
uvicorn app.main:app --reload --port 8000
```

Verify:

```bash
curl http://localhost:8000/health
curl http://localhost:8000/health/firebase
```

The second call is the meaningful one — it performs a real Firestore read and returns `503` if the credentials or project ID are wrong.

### Mobile setup

```bash
cd peersync_mobile
flutter pub get
flutter devices
flutter run
```

Firebase configuration is checked in as `lib/firebase_options.dart`, and Android additionally has `android/app/google-services.json`. There is **no** `ios/Runner/GoogleService-Info.plist` in the repository, so iOS and macOS will need it generated before those targets will authenticate. To (re)generate the full configuration against a project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

**API base URL resolution** (`lib/config/api_config.dart`) is platform-aware:

| Target | Default |
| --- | --- |
| Android emulator | `http://10.0.2.2:8000` |
| Web | `http://localhost:8000` |
| iOS / desktop / physical device | `http://localhost:8000` |

`10.0.2.2` is the Android emulator's alias for the host machine. A **physical device** cannot reach `localhost`, so override it:

```bash
flutter run --dart-define=PEERSYNC_API_BASE_URL=http://192.168.1.50:8000
```

### Web / PWA setup

The `web/` directory is complete: `index.html` with a boot splash, `manifest.json`, `firebase-messaging-sw.js`, and the full icon set including maskable variants.

Development:

```bash
cd peersync_mobile
flutter run -d chrome
```

Or without Chrome, on a fixed port:

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Production build:

```bash
flutter build web --release \
  --dart-define=PEERSYNC_API_BASE_URL=https://api.yourdomain.com \
  --dart-define=PEERSYNC_WEB_VAPID_KEY=<your-web-push-vapid-key>
```

Output is in `peersync_mobile/build/web/`. Serve it over **HTTPS or localhost** — service workers, PWA installation and web push all require a secure context:

```bash
cd build/web && python3 -m http.server 8080
```

For a real deployment, Firebase Hosting is the natural fit (SPA rewrite all paths to `/index.html`):

```bash
npm install -g firebase-tools
firebase login
firebase init hosting          # public dir: build/web, configure as SPA: yes
firebase deploy --only hosting
```

**CORS.** `app/main.py` reads `settings.cors_origin_list`, which splits `CORS_ALLOW_ORIGINS` on commas. The default is `*`, which works because `allow_credentials=False`. When you deploy, set the real origins:

```bash
CORS_ALLOW_ORIGINS=https://peersync.example.com,http://localhost:8080
```

* * *

## Configuration reference

### Backend environment variables

| Variable | Required | Default | Notes |
| --- | --- | :-: | --- |
| `FIREBASE_PROJECT_ID` | ✅ | — | Firebase project ID. |
| `FIREBASE_CREDENTIALS_PATH` | ✅ | — | Path to the service account JSON. |
| `CORS_ALLOW_ORIGINS` | ❌ | `*` | Comma-separated origin allowlist. |

Settings are loaded from `peersync_backend/.env` via `pydantic-settings`. Unknown keys are ignored (`extra="ignore"`).

### Flutter compile-time defines

| Define | Required | Notes |
| --- | --- | --- |
| `PEERSYNC_API_BASE_URL` | Production | Overrides the platform default API URL. |
| `PEERSYNC_WEB_VAPID_KEY` | Web push | From Firebase Console → Project Settings → Cloud Messaging → Web Push certificates. Web push is skipped when absent; Android and iOS are unaffected. |

* * *

## Accessibility

The app targets **WCAG 2.2 Level AA**. The work is concentrated in `lib/core/a11y/`, `lib/theme/app_colors.dart` and `lib/widgets/shared_widgets.dart`.

**Colour and contrast.** The brand palette is unchanged — navy `#0A2342` on `#F2F5FF`. Secondary text, borders and status colours were re-picked so every pair meets its threshold. Documented ratios against the app background: primary `14.47:1`, `textSecondary` `6.91:1`, `textMuted` `5.41:1`, `borderStrong` `4.37:1`, success `6.55:1`, warning `6.51:1`, danger `5.94:1`, info `8.01:1`. The older `#64748B` muted tone measured `4.37:1` and failed AA for normal text, so it was darkened. The pale `#D8E1F0` border is retained only for decorative dividers; anything forming the sole visual boundary of a control uses `borderStrong`.

**Meaning is never carried by colour alone.** Statuses pair colour with a text label and an icon. `lib/core/a11y/status_presentation.dart` centralises the human-readable wording so the same status reads identically everywhere.

**Semantics.** Interactive widgets carry labels, roles and states; decorative icons are excluded with `ExcludeSemantics`; grouped content uses `MergeSemantics` to avoid duplicate announcements; dynamic regions use `liveRegion`; and `SemanticsService.sendAnnouncement` announces state changes such as a submission being approved.

**Keyboard and focus.** Logical focus order, visible focus indicators, focus moved into dialogs on open and returned to the trigger on close, no focus traps, and a keyboard alternative for every gesture-only action.

**Targets and motion.** Minimum 48×48 tap targets (`AppA11y.minTapTarget`), and `AppA11y.motion(context)` collapses animation durations to zero when the platform requests reduced motion.

**Text scaling.** Layouts are tested against 200% text scaling; buttons use `ConstrainedBox(minHeight:)` rather than fixed heights so wrapped labels grow instead of clipping.

**Forms and errors.** Every field has a visible, programmatically associated label. Errors are announced, described in plain language, and paired with a recovery action. Destructive actions require confirmation.

* * *

## Offline support

`lib/core/cache/offline_cache.dart` provides a 72-hour cache, and `lib/services/api_service.dart` wires it into the request path.

The strategy is **network-first with cache fallback**, not cache-first. A successful response is written to the cache and returned; a timeout or transport failure falls back to the cached copy if it is still within its TTL. An `ApiException` (401, 403, 404, 409 and friends) is deliberately **not** masked by stale data — a permission error must surface as a permission error, not as yesterday's list.

Cache keys are namespaced per user UID (`peersync.cache.v1.<uid>.<path>?<sorted-query>`), so two accounts on a shared device never see each other's data. Sign-out calls `OfflineCache.clearForUser(uid)`. Expired entries are pruned on read and on start-up.

Cacheable segments are limited to read paths: `auth`, `projects`, `groups`, `milestones`, `tasks`, `submissions`, `announcements`, `notifications`. Writes are never cached.

The UI reflects connectivity through `ApiService.offline`, a `ValueNotifier<bool>`. When it flips true, the shell shows an offline banner with a retry action.

On web, `shared_preferences` is backed by `localStorage`, so the same cache works in the browser — this is data caching, separate from and layered on top of Flutter's generated asset service worker.

* * *

## Push notifications

`lib/core/push/push_notification_service.dart` handles the client; `app/services/push_service.py` handles delivery.

**Topics.** Every device subscribes to `all_users` plus either `role_professors` or `role_students`.

**Registration flow.** The service requests permission, subscribes to topics, detaches any stale listeners, attaches listeners, then calls `register()`. The order matters: in `firebase_messaging` 17, `onRegistered` is a broadcast stream fed by a native callback and does not replay, so a listener attached after registration would miss the event. Registration waits for the stream with a 20-second timeout. The resulting token is POSTed to `/notifications/devices` along with the platform.

**Sign-out.** `unregister()` deletes the token from the backend, unsubscribes from topics, detaches listeners and calls `unregister()` on the plugin. Detaching listeners here is what prevents a duplicate-banner bug: without it, signing out and back in would attach a second listener set and every foreground message would appear twice.

**Background messages.** `web/firebase-messaging-sw.js` initialises the compat SDK and handles background delivery on web. It lives on Firebase's dedicated push scope and coexists with Flutter's generated `flutter_service_worker.js`. The Dart-side `onBackgroundMessage` handler is guarded with `!kIsWeb` because the web platform throws for that API.

**Delivery is best-effort.** `send_push_to_users` chunks requests at 500 tokens (the FCM multicast limit), deletes tokens that come back `UnregisteredError` or `SenderIdMismatchError`, and logs failures with `logger.exception` without propagating them.

**Audience parity.** `send_announcement_push` lazily imports the same recipient-resolution function used for in-app notifications, so the push audience is guaranteed to match the in-app audience rather than being recomputed from a second, possibly divergent, query.

* * *

## Testing

**Backend static checks:**

```bash
cd peersync_backend
ruff check app
python -m compileall app
```

**Flutter static analysis:**

```bash
cd peersync_mobile
flutter analyze
```

`analysis_options.yaml` extends `flutter_lints` and promotes two rules to build-breaking errors: `avoid_print` and `use_build_context_synchronously`. It also enables lifecycle and async-safety rules (`unawaited_futures`, `cancel_subscriptions`, `close_sinks`).

**Flutter tests:**

```bash
cd peersync_mobile
flutter test
```

⚠️ `test/widget_test.dart` is still the Flutter template's counter smoke test. It pumps `PeerSyncApp` and asserts on a counter that does not exist, so it will fail. It should be replaced with real tests — the highest-value first targets are the submission state machine, the announcement recipient resolution, and `recalculate_task_status`.

**Manual checks worth doing before any release:**

-   Sign in as a Professor and as a Student; confirm each sees only their own navigation items.
-   Confirm a Student cannot reach professor routes (the API should return `403`, not the UI merely hiding a button).
-   Submit work, then try to submit again while `pending` — expect a conflict.
-   Request a revision, then resubmit — expect success.
-   Approve — then confirm the task status recalculated without manual intervention.
-   Publish a group-targeted announcement and confirm only that group's students are notified.
-   Turn off the network and confirm cached screens still render with the offline banner.
-   Enable a screen reader (TalkBack or VoiceOver) and walk the main flows.
-   Set system text size to 200% and confirm nothing clips.

* * *

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `401 Invalid or expired authentication token` | Token expired or revoked; sign out and back in. Check device clock skew. |
| `403` on a route that works for another user | Role mismatch in `users/{uid}.role`, or `isActive` is false. |
| `/health/firebase` returns `503` | Bad `FIREBASE_CREDENTIALS_PATH`, wrong `FIREBASE_PROJECT_ID`, or the service account lacks Firestore access. |
| `FileNotFoundError: Firebase service account file not found` | Relative path resolved against `peersync_backend/`, not the shell's CWD. |
| Android emulator cannot reach the API | Use `10.0.2.2`, not `localhost`. |
| Physical device cannot reach the API | Pass `--dart-define=PEERSYNC_API_BASE_URL=http://<lan-ip>:8000` and add that origin to CORS. |
| Web build: `XMLHttpRequest error` | Origin missing from `CORS_ALLOW_ORIGINS`. |
| Web build: requests go to `localhost:8000` in production | `PEERSYNC_API_BASE_URL` was not passed at build time. |
| Web build: blank page | Opened via `file://`. Serve over HTTP. |
| No PWA install prompt | Not HTTPS or localhost, or `manifest.json` not served at the site root. |
| Web push prompt never appears | `PEERSYNC_WEB_VAPID_KEY` missing, or permission previously denied (reset in browser site settings). |
| Push works on Android but not web | Check the service worker scope and the VAPID key in the browser console. |
| Duplicate foreground banners | Listeners were attached twice — verify `_detachListeners()` runs before `register()`. |
| Stale app after deploy | Service worker cache; hard reload or bump the build. |

* * *

## Known limitations

Stated plainly so nobody assumes more than has been verified.

-   **`test/widget_test.dart` is the unmodified Flutter template test and will fail.** No meaningful automated test suite exists yet.
-   **`flutter analyze`, `flutter test` and `flutter build web` have not been run against this branch in a controlled environment.** The code has been reviewed statically (delimiter balance, unused imports, Ruff, `py_compile`) but not compiled.
-   **Accessibility is a target, not a certification.** Contrast ratios were computed from the palette values; screen-reader behaviour, 200% scaling and keyboard traversal have not been verified on physical devices.
-   **Push delivery has not been tested end to end** on a real device or browser.
-   **Offline behaviour has not been exercised** against a real network partition.
-   **PWA installability and maskable icon cropping** have not been verified in Chrome or on Android.
-   **No file upload storage is implemented.** Submissions record `fileName`, `fileType` and an optional `driveFileId`; there is no upload endpoint or storage bucket integration in this repository.
-   **`requirements.txt` is a full `pip freeze`**, so it includes transitive and unrelated packages (`SQLAlchemy`, `psycopg`, `bcrypt`, `passlib`, `sentry-sdk`, `opentelemetry-*`). A curated dependency list would be smaller and easier to audit.
-   **No pagination on list endpoints.** Fine at capstone scale, not at thousands of records.
-   **No rate limiting or request-level audit logging.**

* * *

## Contributing

**Branching.** Work on `DevFeatures` or a feature branch cut from it. Do not commit directly to `main`.

**Before opening a pull request:**

```bash
cd peersync_backend && ruff check app
cd ../peersync_mobile && flutter analyze && flutter test
```

**Conventions worth respecting:**

-   Do not rename Firestore collections or fields. `notifications.Title` in particular is intentional.
-   Do not change API routes or request/response shapes without updating both the Dart client and the Pydantic schemas in the same change.
-   Keep review actions in Progress Monitoring and submission actions in Activities.
-   Never introduce a manual task-status control; status is derived by `task_status_service`.
-   Do not treat Group Leader as a role.
-   Preserve the navy `#0A2342` / `#F2F5FF` identity and the existing navigation structure.
-   Never commit `.env`, service account JSON, or any credential.

* * *

## License

No license file is present in this repository. Treat it as all rights reserved until one is added.