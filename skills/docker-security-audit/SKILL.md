---
name: docker-security-audit
description: Audit Docker and container infrastructure for security misconfigurations.
tags: [security, docker, infrastructure, autonomous]
---

# Docker Security Audit

Audit all Docker and container configuration files for security best practices.

## AUTONOMOUS WORKFLOW

### Step 1: Find Docker Files
```bash
find . -name "Dockerfile*" -o -name "docker-compose*" -o -name ".dockerignore" 2>/dev/null
```

### Step 2: Dockerfile Audit
For each Dockerfile check:
- Running as root (no USER directive)
- Secrets in ENV or ARG
- Unpinned base images (:latest)
- COPY .env or sensitive files
- Unnecessary packages installed
- Missing health checks
- Multi-stage build (separate build/runtime)
- .dockerignore exists and excludes .env, .git, node_modules

### Step 3: Docker Compose Audit
- Exposed ports to 0.0.0.0 (should bind to 127.0.0.1 for internal services)
- Secrets passed as environment variables (should use Docker secrets or volume mounts)
- Privileged mode enabled
- Volume mounts exposing host filesystem
- Missing resource limits (memory, CPU)
- Missing restart policies
- Missing health checks

### Step 4: Generate Report
Write `docker-security-report.md` with findings and fixes.
