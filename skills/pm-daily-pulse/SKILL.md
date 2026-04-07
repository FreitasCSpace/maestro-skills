---
name: pm-daily-pulse
description: Daily sprint standup digest — fetches sprint tasks from ClickUp, groups by assignee, checks stale/blocked, posts manager-briefing digest to Slack. Idempotent — updates existing message.
---

# PM Daily Pulse

**Fully autonomous. Read-only on ClickUp. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_STANDUP etc). If channel not found, FAIL — NEVER substitute.
- Read-only on ClickUp — NEVER creates, updates, or deletes tasks
- Idempotent Slack posts — updates existing digest if already posted today
- No sprint → write /tmp/no-sprint sentinel and skip remaining steps (do NOT exit)
- **ALL API responses go to /tmp files. Only read summaries into context.**

---

## EXECUTION PROTOCOL

Execute steps **one at a time** in order.

**For each step:**
1. Read the step file listed below using the Read tool
2. Execute the bash block exactly as written
3. Check output before proceeding
4. If a sentinel file is set (`/tmp/no-sprint`), skip all remaining steps

**Do not read ahead.** Only load the next step file after the current step completes successfully.

---

## STEPS

| # | File | Description |
|---|------|-------------|
| 0 | [steps/step-0-load-context.md](steps/step-0-load-context.md) | Source shared context, clear sentinels |
| 1 | [steps/step-1-find-sprint.md](steps/step-1-find-sprint.md) | Detect active sprint → /tmp/sprint-info.json |
| 2 | [steps/step-2-fetch-tasks.md](steps/step-2-fetch-tasks.md) | Paginated task fetch → /tmp/sprint-tasks.json |
| 3 | [steps/step-3-stale-check.md](steps/step-3-stale-check.md) | Stale task check + open PRs → /tmp/stale-tasks.tsv, /tmp/open-prs.txt |
| 4 | [steps/step-4-build-digest.md](steps/step-4-build-digest.md) | Build Manager Briefing digest → /tmp/sprint-health.md |
| 5 | [steps/step-5-post-slack.md](steps/step-5-post-slack.md) | Post digest to Slack (idempotent) |

---

## /tmp FILE MAP

| File | Written by | Read by |
|------|-----------|---------|
| /tmp/no-sprint | Step 1 | Steps 2–5 (sentinel — skip if exists) |
| /tmp/sprint-info.json | Step 1 | Steps 2, 4, 5 |
| /tmp/sprint-pages.ndjson | Step 2 | Step 2 (intermediate) |
| /tmp/sprint-tasks.json | Step 2 | Steps 3, 4 |
| /tmp/stale-tasks.tsv | Step 3 | Step 4 |
| /tmp/open-prs.txt | Step 3 | Step 4 |
| /tmp/assignees.txt | Step 4 | Step 4 |
| /tmp/person-context.md | Step 4 | Step 4 (AI synthesis input) |
| /tmp/sprint-health.md | Step 4 | Step 5 |
