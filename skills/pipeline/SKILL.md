---
name: pipeline
description: |
  Autonomous dev pipeline — runs the full gstack sprint in one session.
  Reads phase instructions and guides from separate files for each step.
---

# Autonomous Dev Pipeline

You are an autonomous development pipeline. You execute the full gstack sprint
in this single session — from understanding the task to shipping a PR.

**CRITICAL RULES — read these BEFORE doing anything:**

1. Any files in the working directory are STALE. Do NOT read PIPELINE.md.
   Do NOT assume any work is done. This is a BRAND NEW task.
2. Your first action must be to read the task input and clone a fresh repo.
3. NEVER say "already completed" — every run is a new task.

**Read the pipeline rules now:**

```bash
cat ~/.claude/skills/pipeline/guides/rules.md
```

Follow every rule in that file throughout the entire pipeline run.

---

## Step 0 — Setup

**Read and follow the setup phase:**

```bash
cat ~/.claude/skills/pipeline/phases/setup.md
```

Execute every step in that file: read task, authenticate, clone, fetch issue,
download screenshots, install deps, read CLAUDE.md, classify task, branch, push.

---

## Phase 0.5 — Codebase Reconnaissance

**Read and follow the recon phase:**

```bash
cat ~/.claude/skills/pipeline/phases/recon.md
```

Build or load the codebase map. Identify relevant files for the issue.

---

## Phase 1 — Investigate (bug-fix and security-fix only)

Skip for features and refactors.

**Read the gstack investigate skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/investigate/SKILL.md
```

Scope investigation to `## Relevant Files` in PIPELINE.md. Append findings.

```bash
git add PIPELINE.md && git commit -m "pipeline: investigate" && git push
```

---

## Phase 2 — Think (features only)

Skip for bug-fix, security-fix, and refactor.

```bash
cat ~/.claude/skills/gstack/office-hours/SKILL.md
```

Follow the six forcing questions. Append `## Think` to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: think" && git push
```

---

## Phase 3 — Plan (features and refactors only)

Skip for bug-fix and security-fix.

```bash
cat ~/.claude/skills/gstack/plan-eng-review/SKILL.md
```

Append `## Plan` to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: plan" && git push
```

---

## Phase 3.5 — Bootstrap Tests (if no test suite exists)

```bash
TEST_FILES=$(find . -type f \( -name "*.test.*" -o -name "*.spec.*" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -5)
echo "Existing test files: ${TEST_FILES:-NONE}"
```

If no tests exist, bootstrap a test framework appropriate for the project type.
If tests already exist, skip this phase entirely.

---

## Phase 4 — Build

**Read the large files guide first:**

```bash
cat ~/.claude/skills/pipeline/guides/large-files.md
```

**Then read and follow the build phase:**

```bash
cat ~/.claude/skills/pipeline/phases/build.md
```

---

## Phase 4.5 — Design Review (UI changes only)

```bash
cat ~/.claude/skills/pipeline/phases/design-review.md
```

---

## Phase 5 — Review

```bash
cat ~/.claude/skills/gstack/review/SKILL.md
```

Review the diff. Fix issues, max 3 iterations. Append `## Review`.

```bash
git diff main..HEAD 2>/dev/null || git diff develop..HEAD 2>/dev/null || git diff master..HEAD
```

```bash
git add -A PIPELINE.md && git commit -m "pipeline: review" && git push
```

---

## Phase 6 — Security

```bash
cat ~/.claude/skills/gstack/cso/SKILL.md
```

**SCOPE:** Only audit files in the diff. Append `## Security`.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: security" && git push
```

---

## Phase 7 — QA

```bash
cat ~/.claude/skills/gstack/qa/SKILL.md
```

Run automated tests. Append `## QA`.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: qa" && git push
```

---

## Phase 8 — Ship

```bash
cat ~/.claude/skills/pipeline/phases/ship.md
```

---

## Phase 9 — Document Release

```bash
cat ~/.claude/skills/pipeline/phases/doc-release.md
```

---

## Final Output

If task completed:
```
COMPLETE: {PR URL}
Task: {brief description}
Phases: {list of phases completed}
```

If task could not be completed:
```
FAILED: {reason}
Task: {brief description}
Blocker: {what prevented completion}
```
