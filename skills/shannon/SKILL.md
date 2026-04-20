---
name: shannon
version: "1.0.0"
description: "Autonomous AI pentester for web apps and APIs. Run white-box security assessments with Shannon — analyzes source code, identifies attack vectors, and executes real exploits to prove vulnerabilities. Triggered by 'shannon', 'pentest', 'security audit', 'vuln scan'."
argument-hint: 'shannon http://localhost:3000 myapp, shannon --workspace=audit1 http://staging.example.com myrepo'
allowed-tools: Bash, Read, Write, AskUserQuestion, WebSearch
homepage: https://github.com/KeygraphHQ/shannon
repository: https://github.com/KeygraphHQ/shannon
author: KeygraphHQ
license: AGPL-3.0
user-invocable: true
metadata:
  openclaw:
    emoji: "🔐"
    category: "security"
    requires:
      env:
        - ANTHROPIC_API_KEY
      optionalEnv:
        - CLAUDE_CODE_OAUTH_TOKEN
        - CLAUDE_CODE_USE_BEDROCK
        - CLAUDE_CODE_USE_VERTEX
        - AWS_REGION
        - AWS_ACCESS_KEY_ID
        - AWS_SECRET_ACCESS_KEY
      bins:
        - docker
        - git
    primaryEnv: ANTHROPIC_API_KEY
    files:
      - "scripts/*"
    tags:
      - security
      - pentesting
      - pentest
      - vulnerability
      - exploit
      - owasp
      - xss
      - sqli
      - ssrf
      - authentication
      - authorization
      - white-box
      - appsec
---

# ── CONFIGURATION ─────────────────────────────────────────────────────────────
# Edit these values before running. Claude will use them directly — no prompts.

TARGET_URL="http://localhost:3000"          # Target URL to pentest
REPO_NAME="myapp"                           # Source code folder name (inside Shannon's repos/)
REPO_PATH=""                                # Absolute path to source code (leave empty if already in repos/)
SCOPE="full"                                # full | injection | xss | ssrf | auth | authz
WORKSPACE=""                                # Named workspace for resume (leave empty for auto)
AUTH_REQUIRED="false"                       # true | false — set true if app requires login
AUTH_LOGIN_URL=""                           # e.g. http://localhost:3000/login
AUTH_USERNAME=""                            # Login username
AUTH_PASSWORD=""                            # Login password
SHANNON_HOME="${HOME}/shannon"              # Where Shannon is installed

# ── END CONFIGURATION ─────────────────────────────────────────────────────────

# Shannon: Autonomous AI Pentester for Web Apps & APIs

> **Permissions overview:** This skill orchestrates Shannon, a Docker-based pentesting tool that actively executes attacks against a target application. It clones/updates the Shannon repo locally, runs Docker containers, and reads pentest reports. **Shannon performs real exploits — only run against apps you own or have explicit written authorization to test.** Never run against production systems.

Shannon analyzes your source code, identifies attack vectors, and executes real exploits to prove vulnerabilities before they reach production. 96.15% exploit success rate on the XBOW security benchmark. Covers OWASP Top 10: Injection, XSS, SSRF, Broken Auth, Broken AuthZ, and more.

---

## CRITICAL: Safety Warning

Display this once before running — do NOT ask for confirmation, just proceed:

```
⚠️  Shannon executes REAL ATTACKS with mutative effects.
├─ Only run on systems you OWN or have WRITTEN AUTHORIZATION to test
├─ Never target production environments
└─ You are responsible for complying with all applicable laws
```

---

## Read Configuration

Read all values from the CONFIGURATION block at the top of this file. Do not ask the user for any of these — they have already set them by editing the skill.

Display a summary before proceeding:
```
🔐 Shannon Pentest (autonomous mode)
├─ Target:    {TARGET_URL}
├─ Source:    repos/{REPO_NAME}  {REPO_PATH if set}
├─ Scope:     {SCOPE}
├─ Workspace: {WORKSPACE or "auto-generated"}
└─ Auth:      {AUTH_REQUIRED}

Estimated runtime: 1–1.5 hours │ Estimated cost: ~$50 (Claude Sonnet)
```

Then proceed immediately through all steps without stopping to ask questions.

---

## Step 0: Ensure Shannon is Installed

Check if Shannon is cloned locally:

```bash
SHANNON_HOME="${SHANNON_HOME:-$HOME/shannon}"

if [ -d "$SHANNON_HOME" ] && [ -f "$SHANNON_HOME/shannon" ]; then
  echo "Shannon found at $SHANNON_HOME"
  cd "$SHANNON_HOME" && git pull --ff-only 2>/dev/null || true
else
  echo "Shannon not found. Cloning..."
  git clone https://github.com/KeygraphHQ/shannon.git "$SHANNON_HOME"
fi

# Verify Docker is available
if command -v docker &>/dev/null; then
  echo "Docker: $(docker --version)"
else
  echo "ERROR: Docker is required. Install Docker Desktop: https://docker.com/products/docker-desktop"
  exit 1
fi
```

If Shannon is not installed, clone it and inform the user. If Docker is missing, stop and tell them to install it.

**SHANNON_HOME** defaults to `~/shannon`. Users can override with `SHANNON_HOME` env var.

---

## Step 1: Prepare Source Code

Shannon needs the target's source code in `$SHANNON_HOME/repos/{REPO_NAME}/`.

Use REPO_PATH and REPO_NAME from the CONFIGURATION block. Do not ask the user.

```bash
SHANNON_HOME="${SHANNON_HOME:-$HOME/shannon}"
REPO_NAME="{REPO_NAME from config}"
REPO_PATH="{REPO_PATH from config}"

mkdir -p "$SHANNON_HOME/repos"

if [ -n "$REPO_PATH" ] && [ -d "$REPO_PATH" ]; then
  # Link local path into Shannon's repos directory
  if [ ! -d "$SHANNON_HOME/repos/$REPO_NAME" ]; then
    ln -s "$(realpath "$REPO_PATH")" "$SHANNON_HOME/repos/$REPO_NAME"
    echo "Linked $REPO_PATH → repos/$REPO_NAME"
  else
    echo "repos/$REPO_NAME already exists, skipping link"
  fi
elif [ -d "$SHANNON_HOME/repos/$REPO_NAME" ]; then
  echo "repos/$REPO_NAME already present"
else
  echo "ERROR: REPO_PATH not set and repos/$REPO_NAME not found. Edit REPO_PATH in the CONFIGURATION block."
  exit 1
fi
```

---

## Step 2: Configure Authentication (if needed)

If `AUTH_REQUIRED="true"` in the CONFIGURATION block, auto-generate the config file from the AUTH_* values — do not ask the user:

```bash
mkdir -p "$SHANNON_HOME/configs"
cat > "$SHANNON_HOME/configs/target-config.yaml" <<EOF
authentication:
  type: form
  login_url: "{AUTH_LOGIN_URL}"
  credentials:
    username: "{AUTH_USERNAME}"
    password: "{AUTH_PASSWORD}"
  flow: "Navigate to login page, enter username and password, click Sign In"
  success_condition:
    url_contains: "/dashboard"
pipeline:
  max_concurrent_pipelines: 5
EOF
echo "Auth config written to configs/target-config.yaml"
```

If `AUTH_REQUIRED="false"`, skip this step entirely.

---

## Step 3: Verify API Credentials

Check that AI provider credentials are available:

```bash
cd "$SHANNON_HOME"

# Check for Anthropic API key (primary)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "✅ ANTHROPIC_API_KEY is set"
elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "✅ CLAUDE_CODE_OAUTH_TOKEN is set"
elif [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ]; then
  echo "✅ AWS Bedrock mode enabled"
elif [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
  echo "✅ Google Vertex AI mode enabled"
else
  echo "❌ No AI credentials found."
  echo "Set one of: ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, or enable Bedrock/Vertex"
  exit 1
fi
```

If no credentials are found, explain the options:
- **Direct API** (recommended): `export ANTHROPIC_API_KEY=sk-ant-...`
- **OAuth**: `export CLAUDE_CODE_OAUTH_TOKEN=...`
- **AWS Bedrock**: `export CLAUDE_CODE_USE_BEDROCK=1` + AWS credentials
- **Google Vertex**: `export CLAUDE_CODE_USE_VERTEX=1` + service account in `./credentials/`

Also recommend: `export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000`

---

## Step 4: Launch the Pentest

Build the command from config values and launch immediately — no confirmation needed.

```bash
cd "$SHANNON_HOME"

CMD="./shannon start URL={TARGET_URL} REPO={REPO_NAME}"

# Append optional flags from config
[ -n "{WORKSPACE}" ] && CMD="$CMD WORKSPACE={WORKSPACE}"
[ -f "configs/target-config.yaml" ] && CMD="$CMD CONFIG=configs/target-config.yaml"

echo "🚀 Launching: $CMD"
```

Run in background (`run_in_background: true`, timeout 600000ms):
```bash
cd "$SHANNON_HOME" && $CMD
```

The pentest runs in Docker and continues independently.

---

## Step 5: Monitor Progress

While the pentest runs, the user can check status:

```bash
cd "$SHANNON_HOME"

# List active workspaces
./shannon workspaces

# View logs for a specific workflow
./shannon logs ID={workflow-id}
```

Explain the 5-phase pipeline:
```
Shannon Pipeline (5 phases, parallel where possible):
├─ Phase 1: Pre-Recon — Source code analysis + external scans (Nmap, Subfinder, WhatWeb)
├─ Phase 2: Recon — Live attack surface mapping via browser automation
├─ Phase 3: Vulnerability Analysis — 5 parallel agents (Injection, XSS, SSRF, Auth, AuthZ)
├─ Phase 4: Exploitation — Dedicated agents execute real attacks to validate findings
└─ Phase 5: Reporting — Executive summary with reproducible PoCs
```

---

## Step 6: Read and Interpret Results

Reports are saved to `$SHANNON_HOME/audit-logs/{hostname}_{sessionId}/`.

```bash
cd "$SHANNON_HOME"

# Find the latest report
LATEST=$(ls -td audit-logs/*/ 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
  echo "Latest report: $LATEST"
  # Find the main report file
  find "$LATEST" -name "*.md" -type f | head -5
fi
```

Read the report and present a summary:

```
🔐 Shannon Pentest Report: {TARGET}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔴 Critical: {N} vulnerabilities
🟠 High:     {N} vulnerabilities
🟡 Medium:   {N} vulnerabilities
🔵 Low:      {N} vulnerabilities

Top Findings:
1. [CRITICAL] {Vuln type} — {location} — PoC: {brief description}
2. [HIGH] {Vuln type} — {location} — PoC: {brief description}
3. ...

Each finding includes a reproducible proof-of-concept exploit.
```

**IMPORTANT: Shannon's "no exploit, no report" policy means every finding has a working PoC.** But remind the user that LLM-generated content requires human review.

---

## Utility Commands

### Check status
```bash
cd "$SHANNON_HOME" && ./shannon workspaces
```

### View logs
```bash
cd "$SHANNON_HOME" && ./shannon logs ID={workflow-id}
```

### Stop pentest
```bash
cd "$SHANNON_HOME" && ./shannon stop
```

### Stop and clean up all data
```bash
# DESTRUCTIVE — confirm with user first
cd "$SHANNON_HOME" && ./shannon stop CLEAN=true
```

### Resume a previous workspace
```bash
cd "$SHANNON_HOME" && ./shannon start URL={URL} REPO={REPO} WORKSPACE={name}
```

---

## Targeting Local Apps

If the user's app runs on localhost, explain:
```
Shannon runs inside Docker. To reach your local app:
├─ Use http://host.docker.internal:{PORT} instead of http://localhost:{PORT}
├─ macOS/Windows: works automatically with Docker Desktop
└─ Linux: add --add-host=host.docker.internal:host-gateway to docker run
```

Automatically translate `localhost` URLs to `host.docker.internal` in the command.

---

## Configuration Reference

### Environment Variables
| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | One of these | Direct Anthropic API key |
| `CLAUDE_CODE_OAUTH_TOKEN` | required | Anthropic OAuth token |
| `CLAUDE_CODE_USE_BEDROCK` | | Set to `1` for AWS Bedrock |
| `CLAUDE_CODE_USE_VERTEX` | | Set to `1` for Google Vertex AI |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Recommended | Set to `64000` |
| `SHANNON_HOME` | Optional | Shannon install dir (default: `~/shannon`) |

### YAML Config Options
| Section | Field | Description |
|---------|-------|-------------|
| `authentication.type` | `form` / `sso` | Login method |
| `authentication.login_url` | URL | Login page |
| `authentication.credentials` | object | username, password, totp_secret |
| `authentication.flow` | string | Natural language login instructions |
| `authentication.success_condition` | object | `url_contains` or `element_present` |
| `rules.avoid` | list | Paths/subdomains to skip |
| `rules.focus` | list | Paths/subdomains to prioritize |
| `pipeline.retry_preset` | `subscription` | Extended backoff for rate-limited plans |
| `pipeline.max_concurrent_pipelines` | 1-5 | Parallel agent count (default: 5) |

---

## Vulnerability Coverage

Shannon tests 50+ specific cases across 5 OWASP categories:

| Category | Examples |
|----------|----------|
| **Injection** | SQL injection, command injection, SSTI, NoSQL injection |
| **XSS** | Reflected, stored, DOM-based, via file upload |
| **SSRF** | Internal service access, cloud metadata, protocol smuggling |
| **Broken Auth** | Default creds, JWT flaws, session fixation, MFA bypass, CSRF |
| **Broken AuthZ** | IDOR, privilege escalation, path traversal, forced browsing |

---

## Integrated Security Tools (bundled in Docker)

- **Nmap** — port scanning and service detection
- **Subfinder** — subdomain enumeration
- **WhatWeb** — web technology fingerprinting
- **Schemathesis** — API schema-based fuzzing
- **Chromium** — headless browser for automated exploitation (Playwright)

---

## Context Memory

For the rest of this conversation, remember:
- **SHANNON_HOME**: Path to Shannon installation
- **TARGET_URL**: The URL being tested
- **REPO_NAME**: Source code folder name
- **WORKSPACE**: Workspace name (if any)
- **PENTEST_STATUS**: running / completed / stopped

When the user asks follow-up questions:
- Check pentest status and report on progress
- Read and interpret new findings from audit-logs
- Help remediate discovered vulnerabilities with code fixes
- Explain PoC exploits and their impact

---

## Security & Permissions

**What this skill does:**
- Clones/updates the Shannon repo from GitHub to `~/shannon` (or `$SHANNON_HOME`)
- Creates symlinks from user's source code into `~/shannon/repos/`
- Starts Docker containers (Temporal server, worker, optional router) via `./shannon` CLI
- Reads pentest reports from `~/shannon/audit-logs/`
- Optionally creates YAML config files in `~/shannon/configs/`

**What Shannon does (inside Docker):**
- Executes real exploits against the target URL (SQL injection, XSS, SSRF, etc.)
- Scans with Nmap, Subfinder, WhatWeb, Schemathesis
- Automates browser interactions via headless Chromium
- Sends prompts to Anthropic API (or Bedrock/Vertex) for reasoning
- Writes reports to `audit-logs/` directory

**What this skill does NOT do:**
- Does not target any system without user confirmation
- Does not store or transmit API keys beyond the configured provider
- Does not modify the user's source code
- Does not access production systems unless explicitly directed (which it warns against)
- Does not run without Docker — all attack tools are containerized

**Review the Shannon source code before first use:** https://github.com/KeygraphHQ/shannon
