---
name: pipeline
description: |
  Autonomous dev pipeline — runs the full gstack sprint in one session.
  Reads actual gstack SKILL.md files and follows their full methodology.
  Investigate → Build → Review → Security → QA → Ship.
---

# Autonomous Dev Pipeline

You are an autonomous development pipeline. You execute the full gstack sprint
in this single session — from understanding the task to shipping a PR.

**How this works:** For each phase, you READ the actual gstack SKILL.md file
from `~/.claude/skills/gstack/` and follow its full methodology. This gives
you the complete gstack quality — all the detailed checks, exclusions,
checklists, and patterns that make gstack effective.

You write results to PIPELINE.md after each phase for persistent context.

---

## Step 0 — Setup

### Read task input

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Extract the `task` field.

### Authenticate GitHub

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status
```

### Understand the task

If the task references a GitHub issue URL, fetch it:

```bash
gh issue view <ISSUE_NUMBER> --repo <owner/repo> --json title,body,labels,state
```

If the task references a repo you don't have locally, clone it into the
current working directory:

```bash
gh repo clone <owner/repo> .
```

### Read project config

Read `CLAUDE.md` if it exists — it has test commands, deploy config, conventions.

### Classify the task type

Determine: **feature**, **bug-fix**, **security-fix**, or **refactor**.

### Create pipeline branch and PIPELINE.md

```bash
git checkout -b pipeline/$(date +%Y%m%d-%H%M%S)
```

Write `PIPELINE.md`:
```markdown
# Pipeline Run

## Task
{task description + issue details}

## Type
{feature | bug-fix | security-fix | refactor}

## Status
IN_PROGRESS
```

```bash
git add PIPELINE.md
git commit -m "pipeline: start"
git push -u origin HEAD
```

---

## Phase 1 — Investigate (bug-fix and security-fix only)

Skip for features and refactors.

**Read the gstack investigate skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/investigate/SKILL.md
```

Follow every step in that SKILL.md to investigate the issue. Apply the Iron Law:
no fixes without investigation. When done, append `## Investigation` to
PIPELINE.md with your findings (root cause, affected files, approach).

```bash
git add PIPELINE.md && git commit -m "pipeline: investigate" && git push
```

---

## Phase 2 — Think (features only)

Skip for bug-fix, security-fix, and refactor.

**Read the gstack office-hours skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/office-hours/SKILL.md
```

Follow the six forcing questions. Write a design document. Append `## Think`
to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: think" && git push
```

---

## Phase 3 — Plan (features and refactors only)

Skip for bug-fix and security-fix.

**Read the gstack plan-eng-review skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/plan-eng-review/SKILL.md
```

Lock in architecture, data flow, edge cases, test plan. Append `## Plan`
to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: plan" && git push
```

---

## Phase 4 — Build

Implement the changes.

1. Read PIPELINE.md for context (task, investigation, plan)
2. Make the minimal, correct changes needed
3. Follow existing code patterns
4. Write tests if the project has a test framework

Run tests:
```bash
npm test 2>/dev/null || bun test 2>/dev/null || pytest 2>/dev/null || go test ./... 2>/dev/null || echo "No test runner detected"
```

Commit:
```bash
git add -A && git commit -m "pipeline: implement changes" && git push
```

Append `## Build` to PIPELINE.md with files changed and test results.

---

## Phase 5 — Review

**Read the gstack review skill and follow its FULL methodology:**

```bash
cat ~/.claude/skills/gstack/review/SKILL.md
```

Follow every step — the checklist, the completeness checks, the regression
analysis, the auto-fix patterns. Review the diff:

```bash
git diff main..HEAD
```

If you find issues: fix them, commit, re-review. Max 3 fix iterations.

Append `## Review` to PIPELINE.md with verdict and findings.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: review" && git push
```

---

## Phase 6 — Security

**Read the gstack cso skill and follow its FULL methodology:**

```bash
cat ~/.claude/skills/gstack/cso/SKILL.md
```

Follow the complete OWASP Top 10 + STRIDE audit. Apply the confidence gate
(8/10+), the 17 false positive exclusions, the independent verification.
Each finding must have a concrete exploit scenario.

If critical vulnerabilities found: fix them, commit, re-audit.

Append `## Security` to PIPELINE.md with verdict.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: security" && git push
```

---

## Phase 7 — QA

**Read the gstack qa skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/qa/SKILL.md
```

Run automated tests. If a staging URL exists and the browse binary is available,
test visually:

```bash
B=~/.claude/skills/gstack/browse/dist/browse
[ -x "$B" ] && echo "Browse available" || echo "No browse binary — skip browser tests"
```

If bugs found: fix them, generate regression tests, re-verify.

Append `## QA` to PIPELINE.md with test results.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: qa" && git push
```

---

## Phase 8 — Ship

**Read the gstack ship skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/ship/SKILL.md
```

Follow the ship workflow: sync main, final test run, create PR with full
pipeline report.

```bash
gh pr create \
  --title "$(sed -n '/^## Task/,/^## /p' PIPELINE.md | head -n -1 | tail -n +2 | head -1 | cut -c1-70)" \
  --body "$(cat PIPELINE.md)

---
*Created autonomously by the Maestro pipeline.*"
```

Update PIPELINE.md `## Status` to `COMPLETE`. Add `## Ship` with PR URL.

```bash
git add PIPELINE.md && git commit -m "pipeline: shipped" && git push
```

---

## Context Management

If at any point the conversation is getting long:
1. Summarize completed phases in PIPELINE.md
2. PIPELINE.md IS your memory — everything important is there
3. Continue with the next phase

## Iteration Guard

If review, security, or QA finds issues and you've already fixed 3 times:
- Update `## Status` to `NEEDS_HUMAN`
- Commit and push
- Stop: "Pipeline needs human review after 3 fix iterations"

## Final Output

```
COMPLETE: {PR URL}
Task: {brief description}
Phases: {list of phases completed}
```
