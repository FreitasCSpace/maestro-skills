# ClaudeHub SecDevOps Skills

8 autonomous security skills for ClaudeHub. Each takes initial input and runs to completion — no interaction needed.

## Skills

| Skill | Input | What It Does |
|-------|-------|-------------|
| **pr-security-review** | repo + PR number | Full HIPAA/OWASP security review, posts comment on PR |
| **repo-security-audit** | repo path | Comprehensive security scan — OWASP Top 10, HIPAA, secrets, deps |
| **sast-scan** | repo path | Static code analysis for injection, auth gaps, data exposure |
| **dast-scan** | base URL | Dynamic testing of running app — headers, TLS, CORS, probes |
| **dependency-audit** | repo path | CVE scan of all dependencies (npm, pip, pub) |
| **hipaa-compliance-check** | repo path | HIPAA-specific audit — PHI logging, storage, transit, access |
| **secrets-scanner** | repo path | Find leaked API keys, passwords, tokens in code + git history |
| **docker-security-audit** | repo path | Dockerfile + compose hardening check |

## Required Secrets

Set these in ClaudeHub → Settings → Secrets:
- `GITHUB_TOKEN` — needed for pr-security-review and repo-security-audit (to fetch PR diffs)

## All skills are autonomous
Give input → skill runs → get report. No human interaction during execution.
