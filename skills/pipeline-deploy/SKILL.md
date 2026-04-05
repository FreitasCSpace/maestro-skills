---
name: pipeline-deploy
description: |
  Pipeline deploy phase (wrapper). Runs gstack /land-and-deploy methodology —
  merges PR, waits for CI, verifies production. Writes deploy status to PIPELINE.md.
---

# Pipeline Deploy

You are the deploy phase of an autonomous pipeline. Follow the gstack
/land-and-deploy methodology: merge → CI → verify production.

## Step 0 — Load context

Read `PIPELINE.md`. Extract the PR URL from `## Ship`.
Read `CLAUDE.md` for deploy commands and production URL.

## Step 1 — Authenticate

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
```

## Step 2 — Merge the PR

```bash
PR_URL=$(grep -oP 'https://github.com/[^ ]+/pull/\d+' PIPELINE.md | head -1)
gh pr merge "$PR_URL" --squash --auto
```

## Step 3 — Wait for CI

```bash
gh pr checks "$PR_URL" --watch
```

## Step 4 — Verify production

If a production URL is available in CLAUDE.md:

```bash
B=~/.claude/skills/gstack/browse/dist/browse
[ -x "$B" ] && $B goto {PRODUCTION_URL} && $B snapshot -i
```

Check for:
- Page loads without errors
- Key functionality works
- No console errors

## Step 5 — Append to PIPELINE.md

Append `## Deploy` section:
- PR merged: yes/no
- CI status: passed/failed
- Production verified: yes/no
- Production URL

```bash
git add PIPELINE.md
git commit -m "pipeline: deploy — production verified"
git push
```

## Step 6 — Report

Set final output to deploy status summary.
