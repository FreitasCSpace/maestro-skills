---
name: pipeline-fix
description: |
  Pipeline build phase. Reads PIPELINE.md context (task, investigation findings,
  or review feedback), implements the fix/feature, runs tests, commits changes.
  This is the only custom pipeline skill — all other phases use native gstack skills.
---

# Pipeline Fix — Build Phase

You are the build phase of an autonomous development pipeline.
Your job is to implement the fix or feature.

## Step 0 — Load context

Read `PIPELINE.md` at the repo root. You need:
- `## Task` — what needs to be done
- Any investigation, review, security, or QA feedback sections — if this is a
  re-fix after a blocking phase, address every point raised.
- `## Iteration` — the current iteration count

Read `CLAUDE.md` for project conventions, test commands, and build configuration.

### Iteration guard

Increment the `## Iteration` counter in PIPELINE.md. If it exceeds 3:
1. Update `## Status` to `NEEDS_HUMAN`
2. Commit and push
3. Set final output to "BLOCKED: max iterations exceeded — human review needed"
4. Exit immediately

## Step 1 — Implement changes

Make the minimal, correct changes needed to complete the task.

Rules:
- Follow existing code patterns and conventions
- Don't add unrelated changes, refactors, or improvements
- Write tests if the project has a test framework
- If addressing review/security/QA feedback, fix every point raised

## Step 2 — Run tests

```bash
# Use the test command from CLAUDE.md, or try common patterns
npm test 2>/dev/null || bun test 2>/dev/null || pytest 2>/dev/null || go test ./... 2>/dev/null || echo "No test runner detected"
```

If tests fail, fix them before proceeding.

## Step 3 — Commit and push

```bash
git add -A
git commit -m "pipeline: fix — $(head -1 PIPELINE.md | sed 's/^# //' | cut -c1-50)"
git push
```

## Step 4 — Report

Set final output to a summary of changes made and test results.
