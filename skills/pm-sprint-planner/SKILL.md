---
name: pm-sprint-planner
description: Sprint planning and finalization — checks candidates, validates capacity and mix, moves tasks to active sprint, posts plan to Slack. Idempotent — tracks state via sprint-id tag.
---

# PM Sprint Planner

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- SLACK: ONLY post to channels from context.sh ($SLACK_SPRINT, $SLACK_STANDUP, $SLACK_ENGINEERING). If channel not found, FAIL — NEVER substitute. NEVER post to #carespace-team, #general, #eng-general.
- Capacity hard limit: $SPRINT_BUDGET_SP SP / 25 tasks — posts Slack alert and STOPS if exceeded
- Idempotency: `sprint-finalized-{sprint-id}` tag prevents re-processing (sprint-id, not date)
- No auto-create sprints — must exist in ClickUp already
- Never delete tasks
- Sprint mix target: $SPRINT_MIX — warnings posted to Slack and included in report
- ALL API responses go to /tmp files. NEVER dump raw JSON into context.

---

## EXECUTION PROTOCOL

Execute steps **one at a time** in order.

For each step:
1. Read the step file listed below using the Read tool
2. Execute the bash block exactly as written
3. Check output before proceeding
4. If /tmp/planner-skip exists after any step, skip all remaining steps

Do not read ahead. Only load the next step file after the current step completes successfully.

Step 2a only runs if Step 2 wrote `ACTIVE_SPRINT` to `/tmp/planner-mode.txt`.

---

## STEPS

| # | File | Description |
|---|------|-------------|
| 0 | [steps/step-0-load-context.md](steps/step-0-load-context.md) | Source shared context, clear sentinel |
| 1 | [steps/step-1-find-target-sprint.md](steps/step-1-find-target-sprint.md) | Find earliest non-done sprint → /tmp/sprint-state.json |
| 2 | [steps/step-2-check-sprint-state.md](steps/step-2-check-sprint-state.md) | Check active vs empty sprint → /tmp/planner-mode.txt |
| 2a | [steps/step-2a-active-sprint-report.md](steps/step-2a-active-sprint-report.md) | If active: post status report and skip planning |
| 3 | [steps/step-3-fetch-candidates.md](steps/step-3-fetch-candidates.md) | Paginated candidate fetch + idempotency check → /tmp/candidates.json |
| 4 | [steps/step-4-capacity-mix-validation.md](steps/step-4-capacity-mix-validation.md) | Hard capacity guard + soft mix warnings |
| 5 | [steps/step-5-move-to-sprint.md](steps/step-5-move-to-sprint.md) | Move candidates to sprint, tag for idempotency |
| 6 | [steps/step-6-build-plan-report.md](steps/step-6-build-plan-report.md) | Build plan report + post to Slack |

---

## /tmp FILE MAP

| File | Written by | Read by |
|------|-----------|---------|
| /tmp/planner-skip | Steps 1-5 | All steps (sentinel — skip if exists) |
| /tmp/sprint-state.json | Step 1 | Steps 2, 2a, 3, 5, 6 |
| /tmp/sprint-current-tasks.json | Step 2 | Step 2a |
| /tmp/planner-mode.txt | Step 2 | Step 2a |
| /tmp/cand-pages.ndjson | Steps 2a, 3 | Steps 2a, 3 (intermediate) |
| /tmp/candidates.json | Step 3 | Steps 4, 5, 6 |
| /tmp/mix-warnings.txt | Step 4 | Step 6 |
| /tmp/planner-metrics.tsv | Step 4 | Step 6 |
| /tmp/finalize-log.txt | Step 5 | printed to stdout |
| /tmp/sprint-plan.md | Step 6 | Step 6 (Slack post) |
