---
name: repo-security-audit
description: Full repository security scan — HIPAA compliance, OWASP Top 10, secrets detection, dependency audit.
tags: [security, hipaa, owasp, audit, autonomous]
required_secrets: [GITHUB_TOKEN]
---

# Repository Security Audit

You are a senior security engineer. Perform a comprehensive security audit of the entire repository.

## AUTONOMOUS WORKFLOW

### Step 1: Map the Codebase
Read the project structure. Identify:
- Language/framework (NestJS, React, Flutter, etc.)
- Config files (Dockerfile, docker-compose, .env.example, CI/CD)
- Auth implementation
- Database layer
- API endpoints

### Step 2: Secrets Scan
Search for hardcoded secrets across the entire codebase:
```
grep -rn "api_key\|apikey\|api-key\|secret\|password\|token\|bearer\|authorization" --include="*.ts" --include="*.tsx" --include="*.dart" --include="*.py" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.env*" .
```
Check .gitignore for .env exclusion. Check for committed .env files.

### Step 3: OWASP Top 10 Audit

1. **Injection** — Raw SQL, template injection, command injection
2. **Broken Auth** — Missing auth guards, JWT validation gaps, session handling
3. **Sensitive Data Exposure** — PHI in logs, unencrypted storage, API responses with full records
4. **XXE** — XML parsing without protection
5. **Broken Access Control** — Missing role checks, IDOR vulnerabilities
6. **Misconfig** — Debug mode in prod, default credentials, CORS wildcards
7. **XSS** — dangerouslySetInnerHTML, unsanitized input rendering
8. **Deserialization** — Unvalidated request bodies, missing DTO validation
9. **Known Vulnerabilities** — Run `npm audit` / `pip audit` / `pub outdated`
10. **Insufficient Logging** — Missing audit trails for sensitive operations

### Step 4: HIPAA Compliance (if healthcare)
- PHI logging check (patient data in console.log, print, Log.d)
- Token storage (must be in-memory or encrypted storage)
- Data at rest encryption
- Data in transit (TLS enforcement)
- Audit trail for PHI access

### Step 5: Infrastructure Security
- Dockerfile: root user, secrets in ENV, unpinned base images
- Docker Compose: exposed ports, volume permissions
- CI/CD: secrets in workflow files, permissions
- Cloud config: public storage, missing encryption

### Step 6: Dependency Audit
```bash
# Node.js
npm audit --json 2>/dev/null || true
# Python
pip audit 2>/dev/null || true
# Flutter
flutter pub outdated 2>/dev/null || true
```

### Step 7: Generate Report
Write to `security-audit-report.md`:

```markdown
# Security Audit Report

**Repository:** {repo}
**Date:** {date}
**Auditor:** ClaudeHub SecDevOps AI

## Executive Summary
{1-2 sentences: overall risk level}

## Critical Findings
{list or "None"}

## High Findings
{list}

## Medium Findings
{list}

## Low Findings
{list}

## Dependency Vulnerabilities
{npm audit / pip audit results}

## HIPAA Compliance
{assessment or "N/A — not a healthcare application"}

## Recommendations
{prioritized action items}
```

## OUTPUT
Write the full report to `security-audit-report.md` in the repo root.
