---
name: pipeline
description: |
  Autonomous dev pipeline — runs the full gstack sprint in one session:
  Think → Plan → Build → Review → Security → QA → Ship.
  Each phase invokes native gstack skills and writes results to PIPELINE.md.
---

# Autonomous Dev Pipeline

You are an autonomous development pipeline. You will execute the full gstack
sprint — from understanding the task to shipping a PR — in this single session.

Each phase invokes a native gstack skill via its slash command, then captures
results in PIPELINE.md. If context gets heavy, summarize completed phases in
PIPELINE.md and continue.

## Step 0 — Setup

### Read task input

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Extract the `task` field. This is what you need to accomplish.

### Authenticate GitHub

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status
```

### Understand the task

If the task references a GitHub issue URL, fetch it:

```bash
gh issue view <URL> --json title,body,labels,state
```

If the task references a repo you don't have locally, clone it:

```bash
gh repo clone <owner/repo> .
```

### Read project config

Read `CLAUDE.md` if it exists — it has test commands, deploy config, conventions.

### Classify the task type

Determine: is this a **new feature**, **bug fix**, **security fix**, or **refactor**?
This determines which phases to run.

### Create pipeline branch and PIPELINE.md

```bash
git checkout -b pipeline/$(date +%Y%m%d-%H%M%S)
```

Write `PIPELINE.md` with:
```markdown
# Pipeline Run

## Task
{task description + issue details}

## Type
{feature | bug-fix | security-fix | refactor}

## Status
IN_PROGRESS
```

Commit and push:
```bash
git add PIPELINE.md
git commit -m "pipeline: start"
git push -u origin HEAD
```

---

## Phase 1 — Investigate (bug fixes and security fixes only)

Skip this phase for features and refactors.

Run the gstack investigate methodology:

1. Search for the bug/vulnerability in the codebase
2. Trace the code path to find root cause
3. Form hypotheses and test them
4. Identify all affected files

Append `## Investigation` to PIPELINE.md with findings.

```bash
git add PIPELINE.md && git commit -m "pipeline: investigate" && git push
```

---

## Phase 2 — Think (features only)

Skip for bug fixes, security fixes, and refactors.

Work through the six forcing questions:
1. What problem are we actually solving?
2. Who benefits and how?
3. What does the 10-star version look like?
4. What are we NOT building?
5. What could go wrong?
6. How will we know it worked?

Append `## Think` to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: think" && git push
```

---

## Phase 3 — Plan (features and refactors)

Skip for bug fixes and security fixes.

Lock in the technical approach:
- Architecture decisions and data flow
- Edge cases and error handling
- Test plan: what tests to write
- Scope: what's in, what's out

Append `## Plan` to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: plan" && git push
```

---

## Phase 4 — Build

Implement the changes. This is the core development phase.

1. Make the minimal, correct changes needed
2. Follow existing code patterns and conventions
3. Write tests if the project has a test framework
4. If addressing review feedback from a previous iteration, fix every point

Run tests:
```bash
npm test 2>/dev/null || bun test 2>/dev/null || pytest 2>/dev/null || go test ./... 2>/dev/null || echo "No test runner detected"
```

Commit changes:
```bash
git add -A && git commit -m "pipeline: implement changes" && git push
```

Append `## Build` to PIPELINE.md with files changed and test results.

---

## Phase 5 — Review

Now review your own changes as a staff engineer looking for production bugs.

```bash
git diff main..HEAD
```

Review for:
1. **Production bugs** — logic errors, race conditions, null pointers, missing error handling
2. **Completeness** — all edge cases handled? missing validation?
3. **Test coverage** — are changes tested? right assertions?
4. **Regressions** — could changes break existing functionality?

If you find issues: fix them now, commit, then re-review.

Append `## Review` to PIPELINE.md with verdict (APPROVED or findings fixed).

```bash
git add -A PIPELINE.md && git commit -m "pipeline: review complete" && git push
```

---

## Phase 6 — Security

Run a security audit on the diff following gstack /cso methodology.

```bash
git diff main..HEAD
```

Check against OWASP Top 10:
- A01 Broken Access Control
- A02 Cryptographic Failures
- A03 Injection (SQL, XSS, command)
- A05 Security Misconfiguration
- A07 Authentication Failures

Only report findings with 8/10+ confidence and a concrete exploit scenario.

If critical vulnerabilities found: fix them now, commit, re-audit.

Append `## Security` to PIPELINE.md with verdict (PASSED or findings fixed).

```bash
git add -A PIPELINE.md && git commit -m "pipeline: security audit" && git push
```

---

## Phase 7 — QA

Test the changes. Run automated tests first:

```bash
npm test 2>/dev/null || bun test 2>/dev/null || pytest 2>/dev/null || echo "No test runner"
```

If a staging URL is available and the browse binary exists, test visually:

```bash
B=~/.claude/skills/gstack/browse/dist/browse
[ -x "$B" ] && $B goto {STAGING_URL} && $B snapshot -i
```

If bugs found: fix them, add regression tests, re-verify.

Append `## QA` to PIPELINE.md with test results.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: QA complete" && git push
```

---

## Phase 8 — Ship

Create a pull request with the full pipeline report.

```bash
TITLE=$(head -5 PIPELINE.md | grep -A1 "## Task" | tail -1 | cut -c1-70)

gh pr create \
  --title "$TITLE" \
  --body "$(cat PIPELINE.md)

---
*Created autonomously by the Maestro pipeline.*"
```

Append `## Ship` to PIPELINE.md with the PR URL.
Update `## Status` to `COMPLETE`.

```bash
git add PIPELINE.md && git commit -m "pipeline: PR created" && git push
```

---

## Context Management

If at any point the conversation is getting long:
1. Summarize all completed phases into PIPELINE.md
2. The file IS your memory — everything important is written there
3. Continue with the next phase

## Iteration Guard

If review or security finds issues and you've already fixed 3 times:
- Update `## Status` to `NEEDS_HUMAN`
- Commit and push
- Stop and report: "Pipeline needs human review after 3 fix iterations"

## Final Output

Set your final output to:
```
COMPLETE: {PR URL}
Task: {brief description}
Phases: {list of phases completed}
```
