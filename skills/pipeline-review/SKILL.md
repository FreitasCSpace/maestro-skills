---
name: pipeline-review
description: |
  Pipeline code review phase (wrapper). Runs gstack /review methodology —
  staff engineer review for production bugs. Writes findings to PIPELINE.md.
  Exits with FAILED status if critical issues found (triggers re-fix).
---

# Pipeline Review

You are the code review phase of an autonomous pipeline. Follow the gstack
/review methodology: find bugs that pass CI but blow up in production.

## Step 0 — Load context

Read `PIPELINE.md` for task context and changes made.
Read `CLAUDE.md` for project conventions.

## Step 1 — Get the diff

```bash
BASE=$(git merge-base main HEAD 2>/dev/null || echo "main")
git log --oneline $BASE..HEAD
git diff $BASE..HEAD --stat
git diff $BASE..HEAD
```

## Step 2 — Staff engineer review

Review every changed file for:

1. **Production bugs**: Logic errors, race conditions, null pointer risks,
   off-by-one errors, missing error handling that will crash in prod.
2. **Completeness**: Are all edge cases handled? Missing validation?
   Incomplete migrations? Orphaned references?
3. **Test coverage**: Are the changes tested? Are the tests testing the
   right thing? Missing edge case tests?
4. **Regressions**: Could these changes break existing functionality?
   Check all callers of modified functions/APIs.
5. **Security**: Quick scan for injection, auth bypass, data exposure.
   (Deep security audit is done by pipeline-security.)

Auto-fix obvious issues (typos, missing null checks) with atomic commits.

## Step 3 — Append to PIPELINE.md

Append `## Review` section:
- Verdict: **APPROVED** or **BLOCKED**
- Findings: `[CRITICAL]`, `[WARNING]`, `[NOTE]` with file:line
- Auto-fixes applied (if any)
- Summary

```bash
git add -A PIPELINE.md
git commit -m "pipeline: review — $(grep -m1 'Verdict:' PIPELINE.md | sed 's/.*Verdict: //')"
git push
```

## Step 4 — Exit status

If **APPROVED**: exit normally (success). Chain continues to pipeline-security.
If **BLOCKED**: exit with error so Maestro marks the run as FAILED.
  The on_failure trigger will re-fire pipeline-fix with your review feedback.

```bash
# If blocked, exit non-zero so Maestro treats this as FAILED
VERDICT=$(grep -m1 'Verdict:' PIPELINE.md | grep -o 'BLOCKED')
if [ "$VERDICT" = "BLOCKED" ]; then
  echo "BLOCKED: critical issues found — see ## Review in PIPELINE.md"
  exit 1
fi
```
