---
name: sast-scan
description: Static application security testing — scan source code for vulnerabilities without running it.
tags: [security, sast, code-analysis, autonomous]
---

# SAST Scan (Static Application Security Testing)

You are a security code reviewer. Scan the entire codebase for security vulnerabilities through static analysis.

## AUTONOMOUS WORKFLOW

### Step 1: Map the Codebase
Read project structure. Identify all source files, config files, and infrastructure code.

### Step 2: Scan Patterns

#### Injection Flaws
```
# SQL Injection
grep -rn "queryRaw\|execute.*+.*\|format.*sql\|f\".*SELECT\|f\".*INSERT\|f\".*UPDATE\|f\".*DELETE" --include="*.ts" --include="*.py" --include="*.js" .

# Command Injection
grep -rn "exec(\|spawn(\|system(\|popen(\|subprocess\.\|child_process" --include="*.ts" --include="*.py" --include="*.js" .

# Template Injection
grep -rn "dangerouslySetInnerHTML\|v-html\|innerHTML\s*=" --include="*.tsx" --include="*.jsx" --include="*.vue" .
```

#### Authentication & Authorization
```
# Missing auth checks
grep -rn "@Controller\|@Get(\|@Post(\|@Put(\|@Delete(" --include="*.ts" .
# Then verify each has @UseGuards

# JWT issues
grep -rn "verify.*algorithms\|jwt\.decode\|ignoreExpiration" --include="*.ts" --include="*.py" --include="*.js" .
```

#### Secrets & Credentials
```
grep -rn "password\s*=\s*[\"']\|api_key\s*=\s*[\"']\|secret\s*=\s*[\"']\|token\s*=\s*[\"']" --include="*.ts" --include="*.py" --include="*.js" --include="*.env*" --include="*.yml" .
```

#### Data Exposure
```
# PHI/PII in logs
grep -rn "console\.log.*patient\|console\.log.*email\|console\.log.*token\|print.*password\|logger.*ssn" --include="*.ts" --include="*.py" --include="*.dart" .

# Sensitive data in localStorage
grep -rn "localStorage\.set\|sessionStorage\.set\|SharedPreferences" --include="*.ts" --include="*.tsx" --include="*.dart" .
```

#### Infrastructure
```
# Docker security
grep -rn "FROM.*:latest\|USER root\|ENV.*PASSWORD\|ENV.*SECRET\|ENV.*TOKEN" Dockerfile* docker-compose* .

# Exposed ports
grep -rn "0\.0\.0\.0\|EXPOSE\|ports:" docker-compose* .
```

### Step 3: False Positive Filtering
For each finding, read the surrounding code context (10 lines before/after) to determine if it's a real vulnerability or false positive.

### Step 4: Generate Report
Write `sast-scan-report.md`:

```markdown
# SAST Scan Report

**Date:** {date}
**Files Scanned:** {count}
**Findings:** {count by severity}

## Critical
{findings with file:line, description, fix}

## High
{findings}

## Medium
{findings}

## Recommendations
{prioritized remediation plan}
```

## OUTPUT
Write report to `sast-scan-report.md`.
