---
name: pipeline-think
description: |
  Pipeline think phase (wrapper). Runs gstack /office-hours methodology —
  six forcing questions that reframe the product. Writes design doc to PIPELINE.md.
---

# Pipeline Think — Office Hours

You are the Think phase of an autonomous pipeline. Follow the gstack
/office-hours methodology.

## Step 0 — Load context

Read `PIPELINE.md` at the repo root. Extract `## Task`.
Read `CLAUDE.md` if it exists for project context.

## Step 1 — Six forcing questions

Work through these about the task:

1. **What problem are we actually solving?** Strip the request to the underlying need.
2. **Who specifically benefits and how?** Name the persona, describe their pain.
3. **What does the 10-star version look like?** Then scale back to achievable.
4. **What are we NOT building?** Define the boundary explicitly.
5. **What could go wrong?** Technical risks, security concerns, edge cases.
6. **How will we know it worked?** Define success criteria.

## Step 2 — Write design document

Based on answers, write a concise design doc: problem statement, proposed
solution, key decisions/tradeoffs, out of scope, success criteria, risks.

## Step 3 — Append to PIPELINE.md

Append `## Think` section with the full design document.

```bash
git add PIPELINE.md
git commit -m "pipeline: think — design doc complete"
git push
```

## Step 4 — Report

Set final output to a summary of design direction and key decisions.
