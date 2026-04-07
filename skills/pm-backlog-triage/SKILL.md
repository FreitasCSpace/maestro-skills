---
name: pm-backlog-triage
description: Import GitHub issues into ClickUp backlog, deduplicate, normalize priorities, estimate story points, triage, and post health report to Slack. Idempotent — safe to run repeatedly.
---

# PM Backlog Triage

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Delete ClickUp tasks whose linked GitHub issue no longer exists (404/closed) — no cap
- Max per run: 50 creates, 50 SP updates, 100 GH comment upserts
- Only set SP on tasks with zero SP — never overwrite
- Never set priority to urgent unless tagged security/compliance
- Idempotency:
  - URL dedup prevents re-importing the same GH issue
  - **GH bot comment is upserted, never appended** — exactly ONE bot comment per issue, marked `<!-- pm-bot:clickup-link v1 -->`. If the ClickUp URL changes, the existing comment is PATCHed. Duplicates are deleted.
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

---

## EXECUTION PROTOCOL

Execute steps **one at a time** in order.

**For each step:**
1. Read the step file listed below using the Read tool
2. Execute the bash block exactly as written
3. Check output before proceeding

**Do not read ahead.** Only load the next step file after the current step completes successfully.

---

## STEPS

| # | File | Description |
|---|------|-------------|
| 0 | [steps/step-0-load-context.md](steps/step-0-load-context.md) | Source shared context |
| 1 | [steps/step-1-collect-gh-issues.md](steps/step-1-collect-gh-issues.md) | Collect open GitHub issues → /tmp/gh-issues.tsv |
| 2 | [steps/step-2-load-cu-backlog.md](steps/step-2-load-cu-backlog.md) | Load ClickUp backlog paginated → /tmp/cu-backlog.json |
| 3 | [steps/step-3-validate-gh-cu-links.md](steps/step-3-validate-gh-cu-links.md) | GraphQL batch-validate GH↔CU links, delete ghosts, close stale |
| 4 | [steps/step-4-import-new-issues.md](steps/step-4-import-new-issues.md) | Import new GH issues, set SP, assign lead, post bot comment |
| 5 | [steps/step-5-backfill-gh-comments.md](steps/step-5-backfill-gh-comments.md) | Backfill/repair bot comments on all live GH issues |
| 6 | [steps/step-6-estimate-sp.md](steps/step-6-estimate-sp.md) | Estimate SP for tasks missing it |
| 7 | [steps/step-7-triage-report.md](steps/step-7-triage-report.md) | Build triage health report → /tmp/triage-report.md |
| 8 | [steps/step-8-post-slack.md](steps/step-8-post-slack.md) | Post report to Slack |

---

## /tmp FILE MAP

| File | Written by | Read by |
|------|-----------|---------|
| /tmp/gh-issues.tsv | Step 1 | Step 4 |
| /tmp/cu-pages.ndjson | Step 2 | Step 2 (intermediate) |
| /tmp/cu-backlog.json | Step 2 | Steps 3, 6, 7 |
| /tmp/cu-urls.txt | Step 2 | Step 4 |
| /tmp/cu-gh-map.tsv | Step 3 | Steps 4, 5 |
| /tmp/gh-states.tsv | Step 3 | Step 3 (intermediate) |
| /tmp/cu-ghost.tsv | Step 3 | Step 3 (intermediate) |
| /tmp/cu-closed.tsv | Step 3 | Step 3 (intermediate) |
| /tmp/stale-issues-log.txt | Step 3 | Step 7 |
| /tmp/new-issues.tsv | Step 4 | Step 4 (intermediate) |
| /tmp/import-log.txt | Step 4 | Step 7 |
| /tmp/comment-log.txt | Step 5 | Step 7 |
| /tmp/no-sp.json | Step 6 | Step 6 (intermediate) |
| /tmp/sp-log.txt | Step 6 | Step 7 |
| /tmp/triage.json | Step 7 | Step 7 (intermediate) |
| /tmp/triage-report.md | Step 7 | Step 8 |
