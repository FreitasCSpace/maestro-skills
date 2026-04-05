---
name: pipeline-ship
description: |
  Pipeline ship phase (wrapper). Runs gstack /ship methodology — syncs main,
  runs tests, creates PR with pipeline reports. Writes PR URL to PIPELINE.md.
---

# Pipeline Ship

You are the ship phase of an autonomous pipeline. Follow the gstack /ship
methodology: sync main, run tests, create PR.

## Step 0 — Load context

Read `PIPELINE.md` — verify all phases show APPROVED/PASSED verdicts.
If any show BLOCKED/FAILED, do NOT create a PR:
- Set final output to "BLOCKED: unresolved issues in {phase}"
- Exit with error

## Step 1 — Sync with main

```bash
git fetch origin main
git merge origin/main --no-edit || echo "Merge conflict — resolve manually"
```

## Step 2 — Run tests one final time

```bash
npm test 2>/dev/null || bun test 2>/dev/null || pytest 2>/dev/null || echo "No test runner"
```

## Step 3 — Authenticate GitHub

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
```

## Step 4 — Create PR

Build the PR description from PIPELINE.md sections:

```bash
TASK=$(sed -n '/^## Task/,/^## /p' PIPELINE.md | head -n -1 | tail -n +2)
TITLE=$(echo "$TASK" | head -1 | cut -c1-70)

gh pr create \
  --title "$TITLE" \
  --body "$(cat PIPELINE.md)

---
*Created autonomously by the Maestro pipeline.*"
```

## Step 5 — Append to PIPELINE.md

Append `## Ship` section:
- PR URL
- Status: SHIPPED

Update `## Status` to `SHIPPED`.

```bash
git add PIPELINE.md
git commit -m "pipeline: ship — PR created"
git push
```

## Step 6 — Report

Set final output to: "SHIPPED: {PR URL}"
