# CareSpace Codebase Context for AI Agents

> This document gives an AI agent everything it needs to start fixing GitHub issues in the CareSpace ecosystem. Read this first before exploring any repo.

## What CareSpace Is

CareSpace is a **HIPAA-compliant healthcare platform** for AI-assisted physical therapy, posture analysis, and movement health. It handles **PHI (Protected Health Information)**. The platform spans:

- Web app for clinicians (React + TypeScript)
- Admin backend for patient management (NestJS + Prisma + PostgreSQL)
- Mobile apps (Native Android, Native iOS, Flutter, Kiosk)
- Backend services for pose analysis (NestJS + TensorFlow MoveNet) and 3D body modeling (Python + PyTorch)
- Headless CMS for clinical content (Strapi)
- Multi-platform SDK for ROM (Range of Motion) assessments

## Issue Source — Bug Tracker

GitHub issues are auto-created by **carespace-bug-tracker** (Next.js + Anthropic SDK). When a customer reports a bug:

1. Tracker captures: title, description, steps, expected/actual, severity, category, environment, browser
2. Anthropic API enhances with: rootCauseHypothesis, codebaseContext, claudePrompt (4-6 step fix instructions)
3. Issue is created in the appropriate repo with this body structure:

```
## 🐛 Bug Report
### Original User Report
> **{title}**
> {description}

---
### AI-Enhanced Description
{enhancedDescription}

### Root Cause Hypothesis
{rootCauseHypothesis}

### Codebase Context
{codebaseContext}  ← Already mentions specific files/aliases to check

---
## Behavior Analysis
### Expected Behavior
### Actual Behavior
### Gap Analysis

---
## Reproduction Steps

### Attachments
- [screenshot-*.png](https://raw.githubusercontent.com/carespace-ai/carespace-bug-tracker/main/bug-attachments/...)
  OR
- https://github.com/user-attachments/assets/{uuid}  ← needs auth header

---
## Technical Context

### Environment
- **Severity**: low/medium/high/critical
- **Category**: ui/functionality/performance/security
- **Priority**: 1-5
- **Repository**: frontend / backend / mobile-android / mobile-ios / etc
- **Environment**: e.g. Extension - https://develop.carespace.ai/
- **Browser**: e.g. Chrome 144 on macOS

---
## 🤖 Claude Code Fix Instructions
{4-6 numbered steps with specific files and aliases}
```

**Implication for AI agents:** the issue body already contains a `Codebase Context` section with file hints AND a `Claude Code Fix Instructions` section with step-by-step guidance. Read these carefully — they often contain the answer.

## Repository Map

| Repo | Stack | Default Branch | Purpose |
|------|-------|---------------|---------|
| **carespace-ui** | React 18 + TS 5 + Ant Design 5 + Redux Toolkit + CRACO | master | Main clinician web app |
| **carespace-admin** | NestJS 11 + Prisma + PostgreSQL | master | API backend, patient management, auth |
| **carespace-posture-engine** | NestJS 11 + TS 5.3 + TensorFlow MoveNet | master | Posture analysis (Kendall plumb-line) |
| **carespace-3d-body-service** | Python 3.11 + FastAPI + PyTorch | master | 3D body model (sam-3d-body) |
| **carespace-strapi** | Strapi 5 (Node.js) | master | Headless CMS for clinical content |
| **carespace-mobile-android** | Kotlin + Gradle KTS | master | Native Android app |
| **carespace-mobile-ios** | Swift + CocoaPods (Xcodeproj) | master | Native iOS app |
| **carespace_mobile** | Flutter (Dart 2.x — legacy) | master | Older Flutter app |
| **carespace-kiosk** | Flutter 3.10 + Riverpod 3 + go_router | master | Correctional facility kiosk |
| **carespace-sdk** | Dart Flutter module monorepo | master | ROM SDK (embeds in Flutter/iOS/Android) |
| **carespace-bug-tracker** | Next.js 15 + Anthropic SDK + Octokit | master | Auto bug reporting → GitHub issues |

**Pipeline always branches from master, opens PR to `develop`.**

---

## carespace-ui — Web Application (Frontend)

**Repo:** carespace-ai/carespace-ui
**Stack:** React 18, TypeScript 5, Ant Design 5, Redux Toolkit, CRACO (NOT Vite, despite README), Tailwind CSS, Storybook, Playwright

### Commands
```bash
npm install --legacy-peer-deps   # install (max-old-space-size=8192)
npm start                         # craco start
npm run build                     # craco build
npm test                          # craco test
npm run lint                      # eslint, max-warnings 0
npm run lint-fix                  # eslint --fix
npm run test:e2e                  # Playwright (TEST_ENV=local|develop|staging)
npm run storybook                 # port 6006
```

### Architecture — Atomic Design

```
src/
├── components/
│   ├── atoms/        — buttons, inputs, badges, modals (Logo, Modal, Badge, Loading, CommandPalette)
│   ├── molecules/    — composites (FormComponents, WeeklyCalendar, MPVideoRecord)
│   ├── organisms/    — feature components (OVideoPoseEstimatorUpdated, ORom, ORehab, OProgram)
│   ├── templates/    — page layouts (sparse usage)
│   └── pages/        — route-mapped views (PatientDashboard, AdminUnassignedPatients, PostureScan, Rom, Rehab)
├── routers/          — Admin.tsx, SuperAdmin.tsx, Patient.tsx, Public.tsx, Private.tsx, routers.ts
├── stores/           — Redux Toolkit slices (see below)
├── services/         — API clients (RTK Query)
├── api/              — REST clients
├── hooks/            — custom hooks (useTypedDispatch, useTypedSelector)
├── styles/           — design-system.css, tokens/primitives.css, antd-theme.ts
├── icons/            — UntitledIcon system (108 migrated icons)
├── config/navigation/ — admin.tsx, superAdmin.tsx, user.tsx (sidebar config)
├── providers/        — ThemeProvider (dark mode)
└── i18n.ts           — i18next setup
```

### Path Aliases (always use these — never `../../`)

```
@atoms/*       → src/components/atoms/*
@molecules/*   → src/components/molecules/*
@organisms/*   → src/components/organisms/*
@pages/*       → src/components/pages/*
@templates/*   → src/components/templates/*
@stores/*      → src/stores/*
@services/*    → src/services/*
@hooks/*       → src/hooks/*
@contexts/*    → src/contexts/*
@utils/*       → src/utils/*
@routers/*     → src/routers/*
@constants/*   → src/constants/*
@config/*      → src/config/*
@providers/*   → src/providers/*
@styles/*      → src/styles/*
@strapi        → src/Strapi.ts
```

### Redux Slices (organized by feature)

```
@stores/clinical/        — rom, rehab, performance, painAssessment, functionalGoals
@stores/tools/           — coachRom, coachRehab, coachPerformance
@stores/patients/triage/ — newPatients, pendingReview, reviewed, outOfParams, escalationRequired, followUpRequired
@stores/patients/admin/  — adminDashboardPatient
@stores/posture/         — postures, postureAnalysis, postureAnalytics, +6 sub-slices
@stores/activity/        — activityStream, contacts
@stores/shared/          — user, userManagement, adminManagement, settings, patientDetail, onBoard, consentForms
@stores/content/         — reports, myLibrary, survey
@stores/dashboard/       — dashboard, dashboardPreferences
@stores/scan             — scan operations
```

**RTK Query APIs:** settingsApi, surveyApi, userManagementApi, reportsApi, programsApi, rehabApi, romApi, recommendationsApi, preferenceApi, adminGroupsApi

**Always use typed hooks:**
```typescript
import { useTypedDispatch, useTypedSelector } from '@stores/index';
```

### Key Routes (from `src/routers/routers.ts`)

```typescript
ROOT: '/'
NEW_PATIENTS: '/admin/patients/new'
REGISTEREDPATIENTS: '/admin/patients/registered'
UNASSIGNEDPATIENTS: '/admin/patients/unassigned'
ESCALATIONREQUIRED: '/admin/patients/escalation-required'
FOLLOWUPREQUIRED: '/admin/patients/follow-up-required'
PENDINGREVIEW: '/admin/patients/pending-review'
REVIEWED: '/admin/patients/reviewed'
ALLPATIENTS: '/admin/patients'
USERPATIENTVIEW: '/:userId/dashboard'
USERREPORTSUMMARY: '/:userId/report/summary'
USERROMSCAN: '/:userId/rom/scan'
USERROMSUMMARY: '/:userId/rom/summary'
POSTURE_ANALYTICS_SCAN: '/:userId/rom/posture-analytics/scan'
POSTURE_ANALYTICS_SUMMARY: '/:userId/rom/posture-analytics/summary'
SETTINGS_*: '/settings/{general|appearance|integrations|templates|plans|content-library|advanced|groups}'
ADMIN_SDK_API_KEYS: '/admin/sdk/api-keys'
```

**Always import route constants from `@routers/routers` — never hardcode paths.**

### Where to look by issue type

| Issue type | Look in |
|-----------|---------|
| UI bug on a specific page | `src/components/pages/{Feature}/` |
| Component bug | `src/components/atoms/{Component}/` or molecules/organisms |
| Routing / navigation | `src/routers/routers.ts`, `src/routers/Admin.tsx`, `src/config/navigation/{role}.tsx` |
| State management bug | `src/stores/{slice}/` |
| API call bug | `src/services/`, `src/api/`, RTK Query files in stores |
| Styling / theme | `src/styles/design-system.css`, `src/styles/tokens/primitives.css`, `Changes.css` |
| Auth bug | `src/auth/`, `Private.tsx` wrapper |
| Icon bug | `src/components/atoms/Icon/` (UntitledIcon) |
| Translation | `src/locales/{en\|es\|...}.json`, run `npm run i18n:validate` |
| Tests | E2E in `tests/` (Playwright), unit in `src/**/*.test.tsx` (Jest) |

### Critical conventions

- **Atomic Design strict** — never put complex logic in atoms
- **Function components only** — no class components
- **Always create Storybook stories** for new atoms/molecules
- **Linting is strict** — `max-warnings 0`, hardcoded colors/spacing/typography are linted out
- **CommandPalette** (Cmd+K) is a 5-mode state machine in `src/components/atoms/CommandPalette/`
- **AppLayoutWrapper** is the unified layout for all roles (replaced AdminLayout, MLayout)
- **Sidebar** docs at `docs/designs/SIDEBAR_MESSAGE_FLOW.md` — read before touching sidepanel/background/content scripts

---

## carespace-admin — Backend API

**Repo:** carespace-ai/carespace-admin
**Stack:** NestJS 11, Prisma + PostgreSQL, FusionAuth (auth), Express, Socket.IO, Swagger

### Commands
```bash
npm install
npm run build              # nest build
npm run start              # NODE_ENV=localhost
npm run start:dev          # nest start --watch
npm run start:prod         # runs migrations then node dist/main
npm run lint               # eslint --fix
npm test                   # jest
npm run test:unit          # excludes e2e
```

### Modules (one folder per feature in `src/`)

```
src/
├── activitystream/       — patient activity feed
├── admin-group/          — clinic groups + permissions
├── auditReports/         — HIPAA audit logs
├── auth/                 — login, sessions
├── bodyComposition/      — body comp measurements
├── calendar-program/     — exercise programs on calendar
├── calendar-tasks/       — patient tasks
├── client/               — patient management
├── common/               — shared utilities
├── context/              — request context (user, org)
├── dataRetention/        — HIPAA data retention rules
├── dto/                  — Prisma-generated DTOs
├── evaluation/           — clinical evaluations
├── fusionauth/           — FusionAuth integration
├── healthcheck/          — health endpoints
├── lets-move/            — LetsMove sessions
├── metrics/              — analytics
├── migration/            — data migration scripts
├── plans/                — subscription plans
├── poseEstimation/       — pose endpoint
├── postureAnalytics/     — posture session analytics
├── reports/              — report generation
├── rom/                  — Range of Motion assessments
├── romTemplate/          — ROM templates
├── scheduled-activity/   — cron jobs
├── services/             — shared services
├── settings/             — user/org settings
├── stats/                — statistics
├── storage/              — Azure Blob storage (PHI)
├── survey/               — survey responses
├── user/                 — user management
├── vr/                   — VR session integration
├── webhook/              — outbound webhooks
└── main.ts               — app entry
```

### Database — Prisma

- Schema: `prisma/schema.prisma`
- Generator: `prisma-generator-nestjs-dto` outputs to `src/dto/`
- DB: PostgreSQL
- DTOs are auto-generated — modifying them by hand will be overwritten on next `prisma generate`

### Auth & PHI

- **FusionAuth** for SSO/login (OAuth flows in `src/fusionauth/`)
- **NEVER log PHI** (patient data, names, DOB, medical records). Use audit log via `auditReports/` module
- **Storage** for PHI files goes through `src/storage/` (Azure Blob, encrypted)
- HIPAA §164.312 audit logging is mandatory for PHI mutations

### Where to look by issue type

| Issue type | Look in |
|-----------|---------|
| API endpoint bug | `src/{module}/{module}.controller.ts` |
| Business logic | `src/{module}/{module}.service.ts` |
| Database schema | `prisma/schema.prisma` |
| Auth bug | `src/auth/`, `src/fusionauth/` |
| Storage bug | `src/storage/` |
| Audit log | `src/auditReports/` |
| Cron / scheduled | `src/scheduled-activity/` |
| Webhook bug | `src/webhook/` |

---

## carespace-posture-engine — Posture Analysis Backend

**Repo:** carespace-ai/carespace-posture-engine
**Stack:** NestJS 10, TypeScript 5.3, `@tensorflow/tfjs-node` + MoveNet, `sharp`, `@azure/service-bus`, Jest
**NOTE:** README mentions Prisma/PostgreSQL but persistence is REMOVED — service is stateless and queue-driven.

### Purpose
Clinical posture assessment via **Kendall plumb-line methodology**:
- **Lateral:** head/shoulder/upperBody/pelvis/knee → F/A/B (Forward/Aligned/Back)
- **Frontal:** head/shoulder/trunk/pelvis/knee/ankle → L/C/R (Left/Center/Right)
- Lookup syndromes from **243-entry lateral** and **729-entry frontal** permutation tables

### Commands
```bash
npm install
npm run start:dev       # port 3001 (APP_PORT)
npm run build && npm run start:prod
npm test
```
**Env:** `APP_PORT`, `NODE_ENV`, `CORS_ORIGINS`, Azure Service Bus connection vars.

### Architecture — QUEUE-DRIVEN, NOT REST
**The only HTTP route is `GET /health`.** Real work flows through Azure Service Bus:

```
Service Bus
  → ConsumerService → MessageHandlerService → PostureProcessingService
       → ImageProcessorService     (URL fetch + MoveNet keypoints)
       → PlumblineExtractorService (keypoints → plumb-line data)
       → CalculationService → PlumblineEngine
            → classifyAllSegments / classifyAllFrontalSegments
            → lookupPermutation / lookupFrontalPermutation
  → ProducerService (result → bus)
```

**Two ingest message types:**
- `assessment` — downloads image URL, runs MoveNet
- `ingest` — pre-extracted COCO-17 keypoints, skips MoveNet

### Key files
- `src/modules/queue/{consumer,message-handler,producer}.service.ts`
- `src/modules/processing/processing.service.ts` — `processImage`, `processKeypoints`, `validateImageUrl`
  - **Hostname allowlist:** `*.blob.core.windows.net`, `*.carespace.ai`, `localhost`, `127.0.0.1`
- `src/modules/image/image-processor.service.ts` — `fetchImageFromUrl`, `extractKeypoints` (sharp + MoveNet)
- `src/modules/image/plumbline-extractor.service.ts`
- `src/modules/image/{image-annotation,image-cache,image-storage}.service.ts` — Azure Blob
- `src/modules/calculation/engines/plumbline.engine.ts`
- `src/assessment/{classifySegments,frontalClassifySegments,permutationTable,frontalPermutationTable}.ts`
- `src/utils/plumbLineCore.ts`
- `src/types/{coco,messages,postureScanResult}.ts`

### Where to look by issue type
| Issue | Look in |
|-------|---------|
| Image fetch / decode / URL rejected | `image-processor.service.ts`, `validateImageUrl` |
| MoveNet inference / keypoints | `image-processor.service.ts` `extractKeypoints` |
| Plumb-line extraction | `plumbline-extractor.service.ts`, `utils/plumbLineCore.ts` |
| Wrong syndrome classification | `assessment/*ClassifySegments.ts`, `*PermutationTable.ts` |
| Result shape / API response | `types/postureScanResult.ts`, `types/messages.ts` |
| Queue errors | `modules/queue/*.service.ts` |

---

## carespace-3d-body-service — 3D Body Service

**Repo:** carespace-ai/carespace-3d-body-service
**Stack:** Python, FastAPI 0.115 + Uvicorn 0.34, PyTorch + torchvision, Pillow, opencv-python-headless, NumPy, Pydantic v2, huggingface-hub, pyrender, timm, einops, roma, loguru
**Wraps:** Meta's [SAM-3D Body](https://huggingface.co/facebook/sam-3d-body-dinov3) model (cloned via `setup.sh` into `./sam-3d-body/`)

### Purpose
Single-image 3D body mesh reconstruction. Given a base64 RGB image, returns SMPL-style mesh vertices/faces, 2D keypoints, camera translation, focal length, and bbox.

### Commands
```bash
# One-time setup
pip install torch torchvision
./setup.sh                       # clones sam-3d-body repo, installs xtcocotools/pycocotools
pip install -r requirements.txt

# Run
./run_dev.sh                     # uvicorn
docker compose up                # CUDA 12.4 base image
```

**Env:**
- `SAM3D_DEVICE` (`cuda`/`mps`/`cpu`, auto-detected)
- `SAM3D_HF_REPO` (default `facebook/sam-3d-body-dinov3`)
- `CORS_ORIGINS` (defaults: `localhost:3000`, `develop/staging/app.carespace.ai`)

**No README, no pyproject.toml, no automated tests in repo.**

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | `{"status":"ok","service":"sam3d-body"}` |
| `POST /api/v1/jobs` | **Async submit.** Body: `{ image: <base64 or data-URL>, gender?: "male"\|"female" }`. Decodes, resizes to max 512px, spawns daemon thread running `predict()`. Returns `{job_id, status: "processing"}` |
| `GET /api/v1/jobs/{job_id}` | Poll status: `processing` / `complete` / `error`. **In-memory store** (`_jobs` dict) — lost on restart, no TTL |
| `POST /api/v1/reconstruct` | **Legacy synchronous.** 400 bad image, 422 no person detected, 500 inference failure |

### Response shape (`app/schemas.py`)
```python
vertices: list[list[float]]    # Nx3
faces: list[list[int]]         # Mx3
keypoints_2d: list[list[float]]
camera_translation: [tx, ty, tz]
focal_length: float
bbox: [x1, y1, x2, y2]
```

### Key files
- `app/main.py` — FastAPI app, CORS, lifespan model load, in-memory job store, all routes
- `app/model.py` — `load_model()` (singleton `_estimator`), `get_device()`, `predict()`, sys.path injection for `sam-3d-body`
- `app/schemas.py` — Pydantic request/response
- `setup.sh` — clones upstream sam-3d-body
- `run_dev.sh` — uvicorn launcher
- `Dockerfile`, `docker-compose.yml`
- `requirements.txt`

### Notes / quirks
- **MPS (Apple Silicon) does NOT support float64** required by the MHR TorchScript model — `model.py` forces main model to CPU and only uses MPS/GPU for human detector + FOV estimator
- Upstream `load_sam_3d_body_hf` ignores its `device` kwarg → service calls `_hf_download` then `load_sam_3d_body(..., device=...)` directly
- `predict()` only takes the **first detected person** from a list result
- Avoids importing `notebook/utils.py` from sam-3d-body (pulls in pyrender/OpenGL, broken on headless/macOS)
- **Job store is in-memory + per-thread, NOT horizontally scalable**

### Where to look by issue type
| Issue | Look in |
|-------|---------|
| Image decode / resize | `app/main.py` ~lines 110-128 (`create_job`) and ~186-202 (`reconstruct`) |
| Model loading / device / HF download | `app/model.py` `load_model()` + `get_device()` |
| "No person detected" / inference fail | `app/model.py` `predict()` + `_extract_numpy/_extract_scalar` |
| API response shape | `app/schemas.py`, `ReconstructResponse(**result)` in `main.py` |
| Error handling | `main.py` — 400/422/500 paths, async errors written to job dict |
| Job lifecycle / memory leak | `_jobs`, `_jobs_lock`, `_set_job`, `_get_job`, `_run_inference_job` in `main.py` |
| CORS / hosting | `cors_origins` block in `main.py` (override via `CORS_ORIGINS`) |

---

## carespace-strapi — Headless CMS

**Repo:** carespace-ai/carespace-strapi
**Stack:** Strapi 5 (Node.js)
**Purpose:** Stores all clinical content (exercises, surveys, body parts, conditions, etc.). Frontend (`carespace-ui`) reads via Strapi REST/GraphQL.

### Content types (`src/api/`)

Clinical reference data:
- exercise, exercise-category, exercise-position, exercise-progression-step
- exercise-target-muscle-group, exercise-tag, exercise-modification-option
- omni-rom-exercise, omni-rom-program, omni-rom-joint, omni-rom-scan-type
- joint, landmark, body-point, body-region
- posture-alignment, posture-joint, posture-analytic
- pain-cause, pain-duration, pain-frequency, pain-status
- aggravating-factor, relieving-factor, health-sign
- diagnose-code, medical-history, informed-consent
- functional-goal, functional-goal-reason
- survey-template, survey-template-question, survey-template-question-option
- recommendation, recommendation-category, recommendation-persona
- program-template, program-experience-level, program-subgoal, program-workout-type
- premium-plan, frontend-translation, therapist, tool, tag, skill

If an issue mentions clinical content (exercise definitions, survey questions, body parts), it likely lives here, **not** in carespace-ui or carespace-admin.

---

## Mobile Apps

### carespace-mobile-android (Native Kotlin)
- **Package:** `com.nexturn.carespaceai`
- **Build:** Gradle KTS (`build.gradle.kts`)
- **Source:** `app/src/main/java/com/nexturn/carespaceai/`
- **Layouts:** `app/src/main/res/layout*` (XML)
- **Resources:** `app/src/main/res/{drawable,color,font,values}/`

### carespace-mobile-ios (Native Swift)
- **Project:** `CareSpaceMobile.xcodeproj` / `CareSpaceMobile.xcworkspace`
- **Pods:** `Podfile` / `Podfile.lock` (CocoaPods)
- **Source:** `CareSpaceMobile/`
- **Build:** `pod install && xcodebuild -workspace CareSpaceMobile.xcworkspace -scheme CareSpaceMobile`

### carespace_mobile (Legacy Flutter — Dart 2.x)
- **Note:** Old Flutter app, Dart SDK 2.1, http 0.12, rxdart 0.18 — **legacy, do not modify unless explicitly asked**
- **Source:** `lib/main.dart`, `lib/src/`

### carespace-kiosk (Modern Flutter — for Correctional Facilities)
- **Stack:** Flutter, Dart 3.10, Riverpod 3, go_router 14, sqflite_sqlcipher (encrypted SQLite), webview_flutter, mobile_scanner (QR), flutter_secure_storage
- **Purpose:** Patient check-in and wellness companion for correctional facility kiosks
- **Source:** `lib/{app,core,features,l10n,shared}/`, `lib/main.dart`
- **Build:** `flutter pub get && flutter build apk` (or `ios`)

### Where to look (mobile)
- **Pose detection / camera** → likely uses MediaPipe (also embedded via SDK)
- **Auth** → `core/auth` or similar
- **API client** → `core/api` or `core/network`
- **Encrypted local DB** → kiosk uses `sqflite_sqlcipher`
- **Navigation** → `go_router` config (kiosk) or Activity/Fragment routing (Android)

---

## carespace-sdk — ROM Assessment SDK

**Repo:** carespace-ai/carespace-sdk
**Stack:** Dart Flutter module monorepo (`packages/flutter`)
**Purpose:** Embeddable SDK for ROM (Range of Motion) assessments using MediaPipe pose detection. Used by:
- Flutter apps (direct widget)
- Native iOS apps (Swift/UIKit via Flutter module)
- Native Android apps (Kotlin via Flutter module)

### Phase 1 exercises (8 joints)
| Joint | Sides | Normal Range |
|-------|-------|--------------|
| Shoulder Flexion | L+R | 0°–180° |
| Elbow Flexion | L+R | 0°–145° |
| Hip Flexion | L+R | 0°–120° |
| Knee Flexion | L+R | 0°–135° |

### Requirements
- iOS 15.6+
- Android API 24 (Android 7.0)+
- Flutter 3.10.0+

### Docs
- `README.md`, `INTEGRATION.md`, `QUICKSTART.md`, `DEVELOPER_GUIDE.md`, `SECURITY.md`
- `android_integration/`, `ios_integration/` — platform-specific integration guides

---

## Cross-cutting Concerns

### HIPAA Compliance
- **Never log PHI** — names, DOB, medical records, biometric data
- **Audit logs required** for all PHI mutations (HIPAA §164.312(b))
- **Encryption at rest** — Azure Blob (admin), sqflite_sqlcipher (kiosk)
- **TLS in transit** — all API calls
- Look for `auditReports/` (admin), data retention rules in `dataRetention/`

### Auth
- **FusionAuth** for web (carespace-admin → src/fusionauth/)
- **react-auth-kit** for ui (Private.tsx wrapper)
- **JWT** for SDK / mobile (`dart_jsonwebtoken`)

### Internationalization
- Frontend uses i18next + react-i18next
- Translation files in `src/locales/{en,es,...}.json`
- Strapi has `frontend-translation` content type for clinician-managed strings
- Run `npm run i18n:validate` to catch missing keys

### Observability
- **OpenTelemetry** in carespace-ui (`@opentelemetry/*` deps) and carespace-admin
- **NewRelic** in carespace-admin (`src/newrelic.ts`)
- Trace IDs flow through requests

---

## Issue Triage Quick Reference

When you receive an issue, check these in order:

1. **Read the AI-Enhanced section** of the issue body — it tells you what files to check
2. **Read the Claude Code Fix Instructions** — usually 4-6 specific steps
3. **Check the `Repository` field in Environment** — tells you which repo to work in
4. **Check the URL in `Reproduction Steps`** — tells you which page/feature

### Common patterns

| Issue says... | Likely fix in... |
|---------------|-----------------|
| "screen / page / button / form" | carespace-ui — `src/components/pages/{Feature}/` |
| "navigation / sidebar / menu" | carespace-ui — `src/config/navigation/`, `src/routers/` |
| "API returns / 500 / 401" | carespace-admin — `src/{module}/{module}.controller.ts` |
| "wrong angle / pose / posture" | carespace-posture-engine — `src/modules/calculation/` or `src/assessment/` |
| "exercise / clinical content / survey" | carespace-strapi — `src/api/{content-type}/` |
| "ROM scan / camera / joint angle" | carespace-sdk — `packages/flutter/lib/` |
| "Android only" | carespace-mobile-android — `app/src/main/java/com/nexturn/carespaceai/` |
| "iOS only" | carespace-mobile-ios — `CareSpaceMobile/` |
| "kiosk / check-in / correctional" | carespace-kiosk — `lib/features/` |

### Branch strategy
- **All repos:** branch from `master` (or `main` if no `master`)
- **PR target:** `develop` (always — never master directly)
- **Pipeline branches:** `pipeline/issue-{N}-{timestamp}`

### Don't modify
- Auto-generated DTO files in `carespace-admin/src/dto/` (Prisma generates these)
- `carespace_mobile` (legacy Flutter) unless explicitly asked
- Any file with `// AUTO-GENERATED` header

---

## Glossary

- **PHI** — Protected Health Information (HIPAA term)
- **ROM** — Range of Motion (joint mobility assessment)
- **Plumb-line / Kendall** — Posture assessment methodology comparing body landmarks against vertical
- **Triage** — Patient state machine: new → pendingReview → reviewed → followUpRequired/escalationRequired/outOfParams
- **OmniRom** — CareSpace's full-body ROM assessment program
- **MediaPipe** — Google's pose detection library (used in browser, iOS, Android, kiosk via SDK)
- **MoveNet** — TensorFlow pose detection model (used in carespace-posture-engine)
- **CRACO** — Create React App Configuration Override (build tool for carespace-ui, NOT Vite despite README)
