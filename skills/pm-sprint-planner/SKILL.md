---
name: pm-sprint-planner
description: Sprint planning and finalization — checks candidates, validates capacity and mix, moves tasks to active sprint, posts plan to Slack. Idempotent — tracks state via sprint-id tag.
---

# PM Sprint Planner

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_SPRINT, $SLACK_STANDUP, $SLACK_ENGINEERING). If channel not found, FAIL — NEVER substitute. NEVER post to #carespace-team, #general, #eng-general.
- Capacity hard limit: $SPRINT_BUDGET_SP SP / 25 tasks — posts Slack alert and STOPS if exceeded
- Idempotency: `sprint-finalized-{sprint-id}` tag prevents re-processing (sprint-id, not date)
- No auto-create sprints — must exist in ClickUp already
- Never delete tasks
- Sprint mix target: $SPRINT_MIX — warnings posted to Slack and included in report
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | Candidates: $LIST_SPRINT_CANDIDATES | Budget: $SPRINT_BUDGET_SP SP"
rm -f /tmp/planner-skip   # clear sentinel from prior run
```

---

## EXECUTION

### Step 1: Find Target Sprint → /tmp/sprint-state.json

Target sprint = the earliest non-done sprint by start_date (upcoming or just started).
Writes sentinel and stops if no sprint found.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '
      [ .lists[] | select(.status.status != "done") ]
      | sort_by(.start_date // "0" | tonumber)
      | first
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' > /tmp/sprint-state.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-state.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-state.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO SPRINT FOUND — create one in ClickUp first"
  touch /tmp/planner-skip; return 0
fi

echo "Target sprint: $SPRINT_NAME (id: $SPRINT_ID)"
```

### Step 2: Check Sprint State (active vs empty) → /tmp/sprint-current-tasks.json

Saves response to file before branching — prevents silent failure on API error.
If sprint has tasks → report-only mode (Step 2a). If empty → proceed to planning (Step 3).

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)

# Save to file — never pipe directly; protects against silent API failure
cu_api GET "list/$SPRINT_ID/task?include_closed=false&subtasks=true&page=0" \
  > /tmp/sprint-current-tasks.json

TASK_COUNT=$(jq '.tasks | length' /tmp/sprint-current-tasks.json)

if [ -z "$TASK_COUNT" ] || [ "$TASK_COUNT" = "null" ]; then
  echo "ERROR: could not fetch sprint tasks — check CLICKUP_PERSONAL_TOKEN and SPRINT_ID=$SPRINT_ID"
  touch /tmp/planner-skip; return 0
fi

echo "Sprint current tasks: $TASK_COUNT"

if [ "$TASK_COUNT" -gt 0 ]; then
  echo "ACTIVE_SPRINT" > /tmp/planner-mode.txt
else
  echo "EMPTY_SPRINT"  > /tmp/planner-mode.txt
fi
```

### Step 2a: Active Sprint — Status Report Only

Only runs if sprint already has tasks. Read-only. Posts status to Slack, then sets skip sentinel.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && return 0
[ "$(cat /tmp/planner-mode.txt 2>/dev/null)" != "ACTIVE_SPRINT" ] && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-state.json)
DUE_FMT=$(date -d "@$(( DUE_MS / 1000 ))" +%Y-%m-%d 2>/dev/null || echo "no due date")
TASK_COUNT=$(jq '.tasks | length' /tmp/sprint-current-tasks.json)

# Paginate candidates for accurate count
> /tmp/cand-pages.ndjson
PAGE=0
while [ $PAGE -lt 5 ]; do
  cu_api GET "list/$LIST_SPRINT_CANDIDATES/task?include_closed=false&page=$PAGE" > /tmp/cand-page.json
  COUNT=$(jq '.tasks | length' /tmp/cand-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/cand-page.json >> /tmp/cand-pages.ndjson
  echo >> /tmp/cand-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done
CAND_COUNT=$(jq -s '[.[].tasks[]] | length' /tmp/cand-pages.ndjson 2>/dev/null || echo 0)

MSG="*${SPRINT_NAME}* — Active until ${DUE_FMT} | ${TASK_COUNT} tasks in sprint | ${CAND_COUNT} candidates queued for next sprint."
slack_post "$SLACK_SPRINT" "Sprint Status: $SPRINT_NAME" "$MSG" "pm-sprint-planner"
echo "Active sprint reported — planning skipped."
touch /tmp/planner-skip
```

### Step 3: Fetch Sprint Candidates (Paginated) → /tmp/candidates.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)
FINALIZE_TAG="sprint-finalized-${SPRINT_ID}"

> /tmp/cand-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$LIST_SPRINT_CANDIDATES/task?include_closed=false&subtasks=true&page=$PAGE" \
    > /tmp/cand-page.json
  COUNT=$(jq '.tasks | length' /tmp/cand-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/cand-page.json >> /tmp/cand-pages.ndjson
  echo >> /tmp/cand-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:70],
      assignees: [.assignees[].username],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      tags: [.tags[].name]
    }
  ]
  | sort_by((.pri | tonumber), -.sp)
' /tmp/cand-pages.ndjson > /tmp/candidates.json

CAND_COUNT=$(jq 'length' /tmp/candidates.json)
echo "Candidates: $CAND_COUNT tasks"

if [ "$CAND_COUNT" -eq 0 ]; then
  echo "No candidates — team needs to add tasks to Sprint Candidates list"
  slack_post "$SLACK_SPRINT" "Sprint Planner: No Candidates" \
    "Sprint Candidates list is empty. Add tasks before running the planner." "pm-sprint-planner"
  touch /tmp/planner-skip; return 0
fi

# Idempotency check — use sprint-id tag, not date
ALREADY=$(jq --arg t "$FINALIZE_TAG" '[.[] | select(.tags | any(. == $t))] | length' /tmp/candidates.json)
if [ "$ALREADY" -gt 0 ]; then
  echo "Already finalized for sprint $SPRINT_ID ($ALREADY tasks tagged) — skipping"
  touch /tmp/planner-skip; return 0
fi
echo "No finalization tag found — proceeding"
```

### Step 4: Capacity + Mix Validation

Hard limit on SP and task count — posts Slack alert and stops if exceeded.
Mix warnings are soft — included in report and Slack but do not block.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
CAND_COUNT=$(jq 'length' /tmp/candidates.json)
TOTAL_SP=$(jq '[.[].sp] | add // 0' /tmp/candidates.json)

BUGS=$(jq       '[.[] | select(.tags | any(test("bug";"i")))]        | length' /tmp/candidates.json)
FEATURES=$(jq   '[.[] | select(.tags | any(test("feature|enhancement";"i")))] | length' /tmp/candidates.json)
COMPLIANCE=$(jq '[.[] | select(.tags | any(test("compliance|security";"i")))] | length' /tmp/candidates.json)

echo "Capacity: $CAND_COUNT tasks (max 25) | $TOTAL_SP SP (max $SPRINT_BUDGET_SP)"
echo "Mix: $BUGS bugs | $FEATURES features | $COMPLIANCE compliance | Target: $SPRINT_MIX"

# Hard capacity block
if [ "$CAND_COUNT" -gt 25 ] || [ "$TOTAL_SP" -gt "$SPRINT_BUDGET_SP" ]; then
  OVER_MSG="⛔ *Sprint Planner Blocked — Over Capacity*
  Tasks: ${CAND_COUNT}/25 | SP: ${TOTAL_SP}/${SPRINT_BUDGET_SP}
  Remove candidates to get under limits, then run again."
  slack_post "$SLACK_SPRINT" "Sprint Planner Blocked: $SPRINT_NAME" "$OVER_MSG" "pm-sprint-planner"
  echo "BLOCKED: over capacity. Slack alert posted."
  touch /tmp/planner-skip; return 0
fi

# Soft mix warnings — saved to file for report inclusion
> /tmp/mix-warnings.txt
[ "$FEATURES" -lt "$SPRINT_MIN_FEATURES" ] && \
  echo "⚠️ Only $FEATURES features (min $SPRINT_MIN_FEATURES) — consider adding more." >> /tmp/mix-warnings.txt
[ "$COMPLIANCE" -gt "$SPRINT_MAX_COMPLIANCE" ] && \
  echo "⚠️ $COMPLIANCE compliance tasks (max $SPRINT_MAX_COMPLIANCE) — consider deferring some." >> /tmp/mix-warnings.txt

echo "Under capacity — proceeding"

# Persist computed values for Steps 5-6 (avoids re-jq)
printf '%s\t%s\t%s\t%s\t%s\n' \
  "$CAND_COUNT" "$TOTAL_SP" "$BUGS" "$FEATURES" "$COMPLIANCE" \
  > /tmp/planner-metrics.tsv
```

### Step 5: Move Candidates to Sprint → /tmp/finalize-log.txt

Links each candidate to the sprint list via `cu_api`. Tags with `sprint-finalized-{sprint-id}` via `cu_api` (respects retry logic).

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)
FINALIZE_TAG="sprint-finalized-${SPRINT_ID}"
> /tmp/finalize-log.txt

jq -r '.[] | @base64' /tmp/candidates.json \
| while IFS= read -r row; do
  ID=$(echo "$row"   | base64 -d | jq -r '.id')
  NAME=$(echo "$row" | base64 -d | jq -r '.name')
  SP=$(echo "$row"   | base64 -d | jq -r '.sp')

  # Link task to sprint list
  cu_api POST "list/$SPRINT_ID/task/$ID" '{}' > /dev/null

  # Tag for idempotency via cu_api (respects rate-limit retry)
  cu_api POST "task/$ID/tag/$FINALIZE_TAG" '{}' > /dev/null

  echo "MOVED: $NAME (${SP}SP)" >> /tmp/finalize-log.txt
  sleep 0.3
done

echo "=== Move Summary ===" >> /tmp/finalize-log.txt
echo "Total moved: $(grep -c "^MOVED:" /tmp/finalize-log.txt)" >> /tmp/finalize-log.txt
cat /tmp/finalize-log.txt
```

### Step 6: Build Plan Report + Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-state.json)
DUE_FMT=$(date -d "@$(( DUE_MS / 1000 ))" +%Y-%m-%d 2>/dev/null || echo "TBD")

# Read persisted metrics
IFS=$'\t' read -r CAND_COUNT TOTAL_SP BUGS FEATURES COMPLIANCE < /tmp/planner-metrics.tsv

MIX_WARNINGS=$(cat /tmp/mix-warnings.txt 2>/dev/null)

# Task list sorted by priority then SP desc (already sorted in candidates.json)
TASK_LIST=$(jq -r '
  .[] | "• *\(.name)* — _\(.assignees|join(", "))_ `\(.sp)SP` [pri \(.pri)]"
' /tmp/candidates.json | head -25)

{
  printf '# Sprint Plan: %s\n\n' "$SPRINT_NAME"
  printf '## Summary\n'
  printf '- **Tasks:** %s | **Total SP:** %s / %s | **Due:** %s\n' \
    "$CAND_COUNT" "$TOTAL_SP" "$SPRINT_BUDGET_SP" "$DUE_FMT"
  printf '- **Mix:** %s bugs + %s features + %s compliance\n' \
    "$BUGS" "$FEATURES" "$COMPLIANCE"
  printf '- **Target mix:** %s\n' "$SPRINT_MIX"
  [ -n "$MIX_WARNINGS" ] && printf '\n## Warnings\n%s\n' "$MIX_WARNINGS"
  printf '\n## Tasks (by priority)\n%s\n' "$TASK_LIST"
} > /tmp/sprint-plan.md

cat /tmp/sprint-plan.md

BODY=$(tail -n +3 /tmp/sprint-plan.md)   # skip markdown title
slack_post "$SLACK_SPRINT" "Sprint Plan: $SPRINT_NAME" "$BODY" "pm-sprint-planner"
```
