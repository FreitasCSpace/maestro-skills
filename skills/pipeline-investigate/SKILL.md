---
name: pipeline-investigate
description: |
  Pipeline investigation phase (wrapper). Runs gstack /investigate methodology —
  systematic root-cause debugging. Writes findings to PIPELINE.md.
---

# Pipeline Investigate

You are the investigation phase of an autonomous pipeline. Follow the gstack
/investigate methodology: systematic root-cause debugging.

## Step 0 — Load context

Read `PIPELINE.md`. Extract `## Task`.
Read `CLAUDE.md` for project context.

## Step 1 — Systematic investigation

Follow the Iron Law: no fixes without investigation.

1. **Reproduce**: Find the code path. Search for error messages, stack traces,
   failing tests. Understand how the issue manifests.

2. **Hypothesize**: Form 2-3 hypotheses about root cause. Rank by likelihood.

3. **Test hypotheses**: For each hypothesis, find evidence for or against.
   Use Grep, Read, git blame. Don't guess — prove.

4. **Root cause**: Identify the actual cause. Trace data flow to the origin.

5. **Scope**: List all files that need to change. Check for similar patterns
   elsewhere that might have the same issue.

6. **Approach**: Design the fix. Consider edge cases and side effects.

Stop after 3 failed hypotheses — escalate to human review.

## Step 2 — Append to PIPELINE.md

Append `## Investigation` section:
- Root Cause (what is actually wrong and why)
- Affected Files (path + what needs to change)
- Approach (step by step fix plan)
- Risks (potential side effects)

```bash
git add PIPELINE.md
git commit -m "pipeline: investigate — root cause identified"
git push
```

## Step 3 — Report

Set final output to brief summary of root cause and fix approach.
