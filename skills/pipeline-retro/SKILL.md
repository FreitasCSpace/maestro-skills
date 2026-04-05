---
name: pipeline-retro
description: |
  Pipeline retro phase (wrapper). Runs gstack /retro methodology —
  retrospective on the pipeline run. Writes learnings to PIPELINE.md.
  Final phase — marks pipeline COMPLETE.
---

# Pipeline Retro

You are the retrospective phase of an autonomous pipeline. Follow the gstack
/retro methodology. This is the FINAL phase — mark the pipeline complete.

## Step 0 — Load context

Read `PIPELINE.md` — the full pipeline history from start to deploy.

## Step 1 — Pipeline retrospective

Analyze the full pipeline run:

1. **What went well?** Which phases completed smoothly? What was the total
   time from start to deploy?

2. **What was blocked?** Did any phase BLOCK and trigger a re-fix?
   How many iterations were needed? What was the root cause of blocks?

3. **What could be improved?** Were any findings missed by earlier phases?
   Did the investigation correctly identify the root cause?

4. **Metrics**: Total iterations, phases completed, tokens used,
   time per phase.

## Step 2 — Append to PIPELINE.md

Append `## Retro` section:
- What went well
- What was blocked (and why)
- Improvement suggestions
- Metrics

Update `## Status` to `COMPLETE`.

```bash
git add PIPELINE.md
git commit -m "pipeline: retro — pipeline complete"
git push
```

## Step 3 — Report

Set final output to: "COMPLETE: {1-sentence summary of what was shipped}"

This is the last phase. The pipeline is done.
