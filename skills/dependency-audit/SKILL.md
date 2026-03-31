---
name: dependency-audit
description: Audit all project dependencies for CVEs, outdated packages, and license issues.
tags: [security, dependencies, audit, autonomous]
---

# Dependency Audit

You are a security engineer. Audit all dependencies in this project for known vulnerabilities, outdated packages, and license compliance issues.

## AUTONOMOUS WORKFLOW

### Step 1: Detect Package Managers
Look for: package.json, pyproject.toml, requirements.txt, pubspec.yaml, Cargo.toml, go.mod, Gemfile

### Step 2: Run Audits
For each detected package manager:

```bash
# Node.js
npm audit --json 2>/dev/null | head -200
npm outdated --json 2>/dev/null | head -100

# Python
pip audit 2>/dev/null || pip install pip-audit && pip audit
pip list --outdated 2>/dev/null | head -50

# Flutter/Dart
dart pub outdated 2>/dev/null

# Rust
cargo audit 2>/dev/null
```

### Step 3: Analyze Results
For each vulnerability found:
- CVE ID and severity (Critical/High/Medium/Low)
- Affected package and version
- Fixed version available?
- Is it a direct or transitive dependency?
- Is the vulnerable code path reachable?

### Step 4: Generate Report
Write `dependency-audit-report.md`:

```markdown
# Dependency Audit Report

**Date:** {date}
**Packages Scanned:** {count}

## Critical Vulnerabilities
| Package | Current | Fixed | CVE | Description |
|---------|---------|-------|-----|-------------|

## Outdated Packages (Major)
| Package | Current | Latest | Type |
|---------|---------|--------|------|

## Recommendations
1. {prioritized updates}
```

## OUTPUT
Write report to `dependency-audit-report.md`.
