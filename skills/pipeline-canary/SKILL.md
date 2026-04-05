---
name: pipeline-canary
description: |
  Pipeline canary phase (wrapper). Runs gstack /canary methodology —
  post-deploy monitoring loop. Watches for errors, performance regressions.
  Writes monitoring report to PIPELINE.md.
---

# Pipeline Canary

You are the canary monitoring phase of an autonomous pipeline. Follow the
gstack /canary methodology: post-deploy monitoring loop.

## Step 0 — Load context

Read `PIPELINE.md`. Extract production URL from `## Deploy` or `CLAUDE.md`.

## Step 1 — Locate browse binary

```bash
B=~/.claude/skills/gstack/browse/dist/browse
[ -x "$B" ] && echo "Browse: $B" || echo "WARNING: no browse binary"
```

## Step 2 — Monitor loop (3 checks, 2 min apart)

For each check:
1. Load the production URL
2. Check for console errors
3. Check page load time
4. Verify key elements render
5. Compare against baseline (if available)

```bash
$B goto {PRODUCTION_URL}
$B snapshot -i
$B console
```

Wait 2 minutes between checks. Run 3 total checks.

## Step 3 — Append to PIPELINE.md

Append `## Canary` section:
- Status: **HEALTHY** or **DEGRADED**
- Check results (timestamp, load time, errors)
- Performance baseline comparison
- Summary

```bash
git add PIPELINE.md
git commit -m "pipeline: canary — $(grep -o 'HEALTHY\|DEGRADED' PIPELINE.md | tail -1)"
git push
```

## Step 4 — Report

Set final output to canary status. If DEGRADED, include specifics.
