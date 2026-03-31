---
name: carespace-code-review
version: 3.0.0
type: orchestrator
description: Autonomous PR security review for CareSpace — HIPAA/OWASP audit + code quality, posts findings as PR comment.
tags: [orchestrator, code-review, security, carespace, autonomous]
required_secrets: [GITHUB_TOKEN]
---

# CareSpace Code Review Orchestrator

## PURPOSE

Perform a full autonomous PR review for CareSpace AI. Read every changed file, apply the security-auditor checklist against the code-standards-base, and post a unified review as a PR comment.

**This skill is self-contained.** The standards and auditor checklists are embedded below — no external skill loading needed.

---

## AUTONOMOUS WORKFLOW

### Step 1: Fetch PR Data
```bash
gh pr view {pr_number} --repo {repo} --json title,body,additions,deletions,changedFiles,files
gh pr diff {pr_number} --repo {repo}
```
Read the FULL diff. No shortcuts. Chunk large files at 500 lines — read ALL chunks.

### Step 2: Classify Changed Files
- **Backend**: .controller.ts, .service.ts, .guard.ts, .module.ts, schema.prisma
- **Frontend**: .tsx, .ts (components, pages)
- **Mobile**: .dart, .swift, .kt
- **Infra**: Dockerfile, docker-compose, .yml, .env

### Step 3: Security Audit
Apply the full checklist below by file type:

#### TypeScript/React (.ts, .tsx)
- **XSS**: dangerouslySetInnerHTML, unsanitized patient notes
- **PHI Logging**: console.log with patient data without redaction
- **Hardcoded Secrets**: API keys, tokens, passwords in source
- **Auth Missing**: API calls without Authorization header
- **CORS**: Wildcard origins, missing Origin validation
- **LocalStorage PHI**: Patient data in localStorage/sessionStorage

#### NestJS (.controller.ts, .service.ts, .guard.ts)
- **Missing AuthGuard**: Controllers without @UseGuards(AuthGuard)
- **Missing RolesGuard**: Patient endpoints without role check
- **Raw SQL**: Prisma.$queryRawUnsafe with string interpolation
- **PHI in Response**: Full patient records without field filtering
- **Missing DTO Validation**: Endpoints without class-validator
- **Error Leaks**: Stack traces or DB schema in error responses
- **Debug in Prod**: Swagger without NODE_ENV check

#### Prisma (.prisma, migrations)
- **Raw Queries**: $queryRaw with string concatenation
- **Mass Assignment**: Spread from request body in create/update
- **Cascade Deletes**: PHI cascading without audit trail

#### Flutter/Dart (.dart)
- **Token Storage**: SharedPreferences for tokens (use in-memory/secure_storage)
- **HTTP without TLS**: http:// URLs (must be https://)
- **Certificate Bypass**: badCertificateCallback returning true
- **PHI on Disk**: Scan data/screenshots written to device storage
- **Debug Logging**: Print without kDebugMode check

#### Swift/Kotlin (.swift, .kt)
- **Unencrypted Storage**: NSUserDefaults/SharedPrefs for PHI
- **ATS Exception**: HTTP exceptions in App Transport Security
- **PHI Logging**: NSLog/Log.d with patient data

#### Docker/Azure (Dockerfile, compose, .yml)
- **Secrets in Image**: ENV with credentials, COPY .env
- **Root User**: Container running as root
- **Debug Mode**: NODE_ENV not production
- **Base Image**: Using :latest instead of pinned version

### Step 4: Code Quality Check
- Missing error handling, TypeScript `any` usage, null checks
- Missing tests for new endpoints
- Breaking API changes

### Step 5: Score
- Any Critical → **BLOCK**
- Any High → **NEEDS CHANGES**
- Only Medium/Low or clean → **PASS**

### Step 6: Post PR Comment
```bash
gh pr comment {pr_number} --repo {repo} --body "$(cat /tmp/review.md)"
```

---

## SEVERITY (Healthcare)

| Severity | Emoji | HIPAA Impact | Action |
|----------|-------|-------------|--------|
| Critical | 🔴 | Potential breach notification | Block merge |
| High | 🟠 | Audit finding | Fix before merge |
| Medium | 🟡 | Minor audit concern | Fix in sprint |
| Low | ⚪ | No HIPAA impact | Backlog |

---

## COMMENT FORMAT

```markdown
## 🔒 Security Review — {PASS|NEEDS CHANGES|BLOCK}

**PR:** {repo}#{number} — {title}
**Files:** {count} | +{additions} -{deletions}
**Reviewer:** CareSpace SecDevOps AI

### Security Findings

#### {emoji} {Severity}: {Issue Type}
**File:** `{path}:{line}`
**Issue:** {one sentence}
**HIPAA Impact:** {why it matters for patient data}
**Fix:** {specific code fix}

### Code Quality
{notes or "✅ Code quality looks good."}

---
*Automated review by CareSpace SecDevOps AI via ClaudeHub*
```

---

## CARESPACE SECURITY STANDARDS (Reference)

**About:** CareSpace AI is a HIPAA-compliant movement health platform — phone/webcam CV measuring 553+ body landmarks. Processes PHI: patient identifiers, health assessments, body scan imagery.

**Stack:** React 18/TypeScript + NestJS/Prisma + Flutter/Dart + Swift iOS + Kotlin Android. Azure (Container Apps, ACR, Blob, Service Bus, Key Vault). Auth via FusionAuth + JWT + NestJS guards.

**PHI Rules:**
- Never log PHI (userId, patientId, email, token, base64, screenshot, name)
- Tokens: in-memory only, never SharedPreferences/localStorage/disk
- Body scans: base64 in memory → upload → free. Never written to device.
- All API calls: https:// enforced
- JWT tokens: replace with [JWT ***] in any output
- Bearer token + x-api-key on every request

**OWASP Healthcare:**
1. SQL Injection → Prisma only, no raw SQL with interpolation
2. XSS → No dangerouslySetInnerHTML, CSP headers
3. CSRF → NestJS CSRF tokens, SameSite cookies
4. Broken Auth → FusionAuth JWT validation, @UseGuards(AuthGuard) everywhere
5. Misconfig → No debug in prod, no Swagger in prod, no wildcard CORS
6. Data Exposure → Azure Key Vault, no secrets in Dockerfile
7. Access Control → AuthGuard + RolesGuard, patients own data only
8. Deserialization → class-validator DTOs
9. Logging → Audit events without PHI content
10. Dependencies → npm/pub audit, pin versions

**Azure:** Container Apps (no SSH, Key Vault refs, HTTPS-only), Blob (private, SAS min perms), Service Bus (encrypt PHI)
