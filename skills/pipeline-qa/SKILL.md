---
name: pipeline-qa
description: |
  Pipeline QA phase (wrapper). Runs gstack /qa methodology — real browser
  testing via browse binary, bug fixing, regression tests. Writes QA report
  to PIPELINE.md. Exits FAILED if tests fail (triggers re-fix).
---

# Pipeline QA

You are the QA phase of an autonomous pipeline. Follow the gstack /qa
methodology: test with a real browser, find bugs, fix them, generate
regression tests.

## Step 0 — Load context

Read `PIPELINE.md` for task context, changes, and staging URL.
Read `CLAUDE.md` for test commands and staging configuration.

## Step 1 — Locate browse binary

```bash
B=""
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$_ROOT" ] && [ -x "$_ROOT/.claude/skills/gstack/browse/dist/browse" ] && B="$_ROOT/.claude/skills/gstack/browse/dist/browse"
[ -z "$B" ] && B=~/.claude/skills/gstack/browse/dist/browse
[ -x "$B" ] && echo "Browse: $B" || echo "WARNING: browse binary not found — skipping browser tests"
```

## Step 2 — Run automated tests

```bash
# Use test command from CLAUDE.md, or detect
npm test 2>/dev/null || bun test 2>/dev/null || pytest 2>/dev/null || go test ./... 2>/dev/null || echo "No test runner detected"
```

## Step 3 — Browser testing

If a staging URL is available and browse binary exists:

1. Navigate to the staging URL
2. Test the specific changes described in PIPELINE.md `## Changes`
3. Click relevant buttons/links, fill forms
4. Check for visual regressions, console errors, broken layouts
5. Take screenshots of key states

```bash
$B goto {STAGING_URL}
$B snapshot -i
```

## Step 4 — Fix bugs found

If you find bugs during testing:
- Fix them with atomic commits
- Generate a regression test for each fix
- Re-verify the fix

## Step 5 — Append to PIPELINE.md

Append `## QA Report` section:
- Verdict: **PASSED** or **FAILED**
- Automated test results
- Browser test results (PASS/FAIL per test)
- Bugs found and fixed
- Regression tests added
- Summary

```bash
git add -A PIPELINE.md
git commit -m "pipeline: qa — $(grep 'Verdict:' PIPELINE.md | tail -1 | sed 's/.*Verdict: //')"
git push
```

## Step 6 — Exit status

If **PASSED**: exit normally. Chain continues to pipeline-ship.
If **FAILED**: exit with error to trigger re-fix.

```bash
VERDICT=$(grep 'Verdict:' PIPELINE.md | tail -1 | grep -o 'FAILED')
[ "$VERDICT" = "FAILED" ] && echo "FAILED: QA tests failed" && exit 1
```
