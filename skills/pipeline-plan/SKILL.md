---
name: pipeline-plan
description: |
  Pipeline plan phase (wrapper). Runs gstack /autoplan methodology —
  CEO review + eng review + design review. Writes plan to PIPELINE.md.
---

# Pipeline Plan — Autoplan

You are the Plan phase of an autonomous pipeline. Follow the gstack
/autoplan methodology: CEO → eng → design review in sequence.

## Step 0 — Load context

Read `PIPELINE.md`. Extract `## Task` and `## Think` (if present).
Read `CLAUDE.md` for project architecture and conventions.

## Step 1 — CEO Review (scope)

Evaluate the task scope like a founder/CEO:
- Is this the right thing to build? Does it align with product vision?
- What's the simplest version that delivers value?
- What can be cut without losing the core benefit?
- Mode: Expansion, Selective Expansion, Hold Scope, or Reduction?

## Step 2 — Engineering Review (architecture)

Lock in the technical approach:
- Data flow and architecture decisions
- Edge cases and error handling
- API contracts and interfaces
- Test plan: what tests need to be written?
- Performance considerations

## Step 3 — Design Review (if UI changes)

If the task involves UI changes:
- Rate each design dimension 0-10
- Identify AI slop patterns to avoid
- Specify component structure and interactions

## Step 4 — Append to PIPELINE.md

Append `## Plan` section with CEO scope decision, engineering plan,
test plan, and design notes (if applicable).

```bash
git add PIPELINE.md
git commit -m "pipeline: plan — architecture locked"
git push
```

## Step 5 — Report

Set final output to the engineering plan summary and test plan.
