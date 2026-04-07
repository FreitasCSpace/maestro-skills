---
name: pm-retrospective
description: End-of-sprint retrospective — calculates velocity (SP-based), moves carryovers to Sprint Candidates with priority bump, posts retro summary to Slack. Idempotent — uses sprint-id tag to prevent double-processing.
---

# PM Retrospective

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- SLACK: ONLY post to channels from context.sh ($SLACK_SPRINT, $SLACK_STANDUP, $SLACK_ENGINEERING). If channel not found, FAIL — NEVER substitute. NEVER post to #carespace-team, #general, #eng-general.
- Only runs if sprint is PAST due date — sentinel skip if still active
- Idempotency: `retro-{sprint-id}` tag on tasks prevents re-processing (sprint-id, not date)
- Max 15 carryovers — posts Slack alert and STOPS if exceeded
- Never delete tasks. Priority bump capped at 2 (High) unless task has security/compliance tag
- ALL API responses go to /tmp files. NEVER dump raw JSON into context.

---

## EXECUTION PROTOCOL

Execute steps **one at a time** in order.

For each step:
1. Read the step file listed below using the Read tool
2. Execute the bash block exactly as written
3. Check output before proceeding
4. If /tmp/retro-skip exists after any step, skip all remaining steps

Do not read ahead. Only load the next step file after the current step completes successfully.

---

## STEPS

| # | File | Description |
|---|------|-------------|
| 0 | [steps/step-0-load-context.md](steps/step-0-load-context.md) | Source shared context, clear sentinel |
| 1 | [steps/step-1-find-ended-sprint.md](steps/step-1-find-ended-sprint.md) | Find most recently ended non-done sprint → /tmp/retro-sprint.json |
| 2 | [steps/step-2-fetch-tasks.md](steps/step-2-fetch-tasks.md) | Paginated task fetch + idempotency check → /tmp/retro-tasks.json |
| 3 | [steps/step-3-calculate-metrics.md](steps/step-3-calculate-metrics.md) | Compute velocity, health, carryover check → /tmp/retro-report.md |
| 4 | [steps/step-4-move-carryovers.md](steps/step-4-move-carryovers.md) | Move carryovers to candidates, bump priority, tag all tasks |
| 5 | [steps/step-5-post-slack.md](steps/step-5-post-slack.md) | Post retro report to Slack |

---

## /tmp FILE MAP

| File | Written by | Read by |
|------|-----------|---------|
| /tmp/retro-skip | Steps 1, 2, 3 | Steps 1-5 (sentinel — skip if exists) |
| /tmp/retro-sprint.json | Step 1 | Steps 2, 3, 4, 5 |
| /tmp/retro-pages.ndjson | Step 2 | Step 2 (intermediate) |
| /tmp/retro-tasks.json | Step 2 | Steps 3, 4 |
| /tmp/retro-report.md | Step 3 | Step 5 |
| /tmp/retro-move-log.txt | Step 4 | printed to stdout |
