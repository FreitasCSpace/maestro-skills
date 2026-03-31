---
name: hipaa-compliance-check
description: HIPAA compliance audit for healthcare applications — PHI handling, encryption, access controls, audit trails.
tags: [security, hipaa, compliance, healthcare, autonomous]
---

# HIPAA Compliance Check

You are a HIPAA compliance auditor. Scan the codebase for HIPAA violations related to Protected Health Information (PHI) handling.

## AUTONOMOUS WORKFLOW

### Step 1: Identify PHI Touchpoints
Search for code that handles patient data:
```
grep -rn "patient\|health\|medical\|diagnosis\|prescription\|scan\|assessment\|bodyLandmark\|phiData\|protected.*health" --include="*.ts" --include="*.tsx" --include="*.dart" --include="*.py" .
```

### Step 2: PHI Logging Audit
PHI must NEVER appear in logs. Check:
```
grep -rn "console\.log\|console\.error\|console\.warn\|logger\.\|print(\|Log\.d\|Log\.e\|NSLog" --include="*.ts" --include="*.tsx" --include="*.dart" --include="*.swift" --include="*.kt" .
```
For each log statement, check if it could output: userId, patientId, email, name, token, authorization, screenshot, image, base64, health data.

### Step 3: PHI Storage Audit
- Tokens must be in-memory only (never localStorage, SharedPreferences, NSUserDefaults)
- Body scan data must never be written to disk
- Database PHI must be encrypted at rest
- Backups must be encrypted

### Step 4: PHI Transit Audit
- All API calls must use HTTPS
- No certificate bypass in production
- Bearer token + API key on every authenticated request
- No PHI in URL query parameters

### Step 5: Access Control Audit
- Every endpoint handling PHI must have auth guard
- Role-based access: patients see only their own data
- Admin access must be separately guarded
- Audit trail for PHI access events

### Step 6: Generate Report
Write `hipaa-compliance-report.md`:

```markdown
# HIPAA Compliance Report

**Date:** {date}
**Application:** {name}
**Auditor:** ClaudeHub SecDevOps AI

## Compliance Score: {PASS|NEEDS REMEDIATION|FAIL}

## PHI Logging Violations
{findings or "✅ No PHI logging detected"}

## PHI Storage Issues
{findings or "✅ PHI storage compliant"}

## PHI Transit Issues
{findings or "✅ All PHI encrypted in transit"}

## Access Control Gaps
{findings or "✅ Access controls adequate"}

## Remediation Plan
{prioritized fixes}
```
