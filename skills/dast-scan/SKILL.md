---
name: dast-scan
description: Dynamic application security testing — probe running endpoints for vulnerabilities.
tags: [security, dast, testing, autonomous]
---

# DAST Scan (Dynamic Application Security Testing)

You are a penetration tester. Given a base URL, probe the running application for security vulnerabilities.

## AUTONOMOUS WORKFLOW

### Step 1: Discover Endpoints
```bash
# Check for common files
curl -s {base_url}/robots.txt
curl -s {base_url}/sitemap.xml
curl -s {base_url}/.env
curl -s {base_url}/.git/config
curl -s {base_url}/swagger-json || curl -s {base_url}/api-docs
```

### Step 2: Security Headers Check
```bash
curl -sI {base_url}
```
Check for:
- Strict-Transport-Security (HSTS)
- X-Content-Type-Options: nosniff
- X-Frame-Options
- Content-Security-Policy
- X-XSS-Protection
- Referrer-Policy
- Permissions-Policy

### Step 3: TLS/SSL Check
```bash
curl -sI https://{domain} 2>&1 | head -5
# Check certificate expiry
echo | openssl s_client -connect {domain}:443 -servername {domain} 2>/dev/null | openssl x509 -noout -dates 2>/dev/null
```

### Step 4: Common Vulnerability Probes
- Open redirect: `{base_url}/redirect?url=https://evil.com`
- Path traversal: `{base_url}/../../etc/passwd`
- CORS misconfiguration: `curl -H "Origin: https://evil.com" -sI {base_url}`
- Verbose error messages: `{base_url}/api/nonexistent`
- Debug endpoints: `/debug`, `/status`, `/health`, `/metrics`, `/graphql`
- Default credentials on admin panels

### Step 5: API Security (if API detected)
- Missing authentication on endpoints
- Rate limiting (send 20 rapid requests)
- Input validation (oversized payloads, special characters)
- HTTP methods (OPTIONS, PUT, DELETE on read-only endpoints)

### Step 6: Generate Report
Write `dast-scan-report.md` with all findings, severity, and remediation steps.

## RULES
- Only probe the target URL provided. No scope expansion.
- Do not attempt destructive actions (DELETE, data modification).
- Do not attempt credential brute-forcing.
- This is authorized testing only.
