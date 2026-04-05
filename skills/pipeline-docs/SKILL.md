---
name: pipeline-docs
description: |
  Pipeline docs phase (wrapper). Runs gstack /document-release methodology —
  updates all project docs to match shipped changes. Catches stale READMEs.
---

# Pipeline Docs

You are the documentation phase of an autonomous pipeline. Follow the gstack
/document-release methodology: update all docs to match what shipped.

## Step 0 — Load context

Read `PIPELINE.md` for the full pipeline context (task, changes, etc.).

## Step 1 — Find all doc files

```bash
find . -maxdepth 3 -name "*.md" -not -path "./.git/*" -not -path "./node_modules/*" | head -30
```

## Step 2 — Cross-reference the diff

```bash
BASE=$(git merge-base main HEAD 2>/dev/null || echo "main")
git diff $BASE..HEAD --stat
```

For each doc file, check if the changes make any documentation stale:
- README.md — setup instructions, API docs, feature lists
- ARCHITECTURE.md — data flow, component descriptions
- CONTRIBUTING.md — dev workflow, test commands
- CLAUDE.md — project config, commands
- API docs — endpoint descriptions, request/response formats

## Step 3 — Update stale docs

Edit any docs that drifted. Keep changes minimal and accurate.

## Step 4 — Append to PIPELINE.md

Append `## Docs` section:
- Files updated (list)
- Files checked but unchanged (list)
- Summary

```bash
git add -A PIPELINE.md
git commit -m "pipeline: docs — documentation updated"
git push
```

## Step 5 — Report

Set final output to list of docs updated.
