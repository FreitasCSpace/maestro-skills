---
name: pipeline-security
description: |
  Pipeline security audit phase (wrapper). Runs gstack /cso methodology —
  OWASP Top 10 + STRIDE threat model. Writes findings to PIPELINE.md.
  Exits FAILED if critical vulnerabilities found (triggers re-fix).
---

# Pipeline Security

You are the security audit phase of an autonomous pipeline. Follow the gstack
/cso methodology: OWASP Top 10 + STRIDE, zero-noise, high-confidence findings.

## Step 0 — Load context

Read `PIPELINE.md` for task context.
Read `CLAUDE.md` for project security requirements.

## Step 1 — Get the diff

```bash
BASE=$(git merge-base main HEAD 2>/dev/null || echo "main")
git diff $BASE..HEAD
```

## Step 2 — OWASP Top 10 audit

Review every changed file against OWASP Top 10:
- A01 Broken Access Control — missing auth, IDOR, privilege escalation
- A02 Cryptographic Failures — hardcoded secrets, weak hashing
- A03 Injection — SQL, command, XSS, template injection
- A04 Insecure Design — missing rate limits, business logic flaws
- A05 Security Misconfiguration — debug mode, default creds
- A06 Vulnerable Components — known CVEs
- A07 Authentication Failures — weak passwords, session issues
- A08 Data Integrity — deserialization, unsigned updates
- A09 Logging Failures — missing audit trails, PII in logs
- A10 SSRF — unvalidated URLs

Only report findings with 8/10+ confidence. Each must include a concrete
exploit scenario. Apply the 17 false positive exclusions from gstack /cso.

## Step 3 — STRIDE analysis

For each new endpoint or data flow: Spoofing, Tampering, Repudiation,
Information Disclosure, Denial of Service, Elevation of Privilege.

## Step 4 — HIPAA check (if applicable)

If changes touch PHI: encryption at rest/transit, access controls, audit trail,
minimum necessary data exposure.

## Step 5 — Append to PIPELINE.md

Append `## Security` section:
- Verdict: **PASSED** or **BLOCKED**
- OWASP findings with `[CRITICAL]` / `[WARNING]` and file:line
- STRIDE findings
- HIPAA status (if applicable)
- Summary

```bash
git add PIPELINE.md
git commit -m "pipeline: security — $(grep -m1 'Verdict:' PIPELINE.md | tail -1 | sed 's/.*Verdict: //')"
git push
```

## Step 6 — Exit status

If **PASSED**: exit normally. Chain continues to pipeline-qa.
If **BLOCKED**: exit with error to trigger re-fix.

```bash
VERDICT=$(grep 'Verdict:' PIPELINE.md | tail -1 | grep -o 'BLOCKED')
[ "$VERDICT" = "BLOCKED" ] && echo "BLOCKED: critical vulnerabilities" && exit 1
```
