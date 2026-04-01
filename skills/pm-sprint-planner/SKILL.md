---
name: pm-sprint-planner
description: Sprint planning and finalization — checks candidates, moves tasks to active sprint with capacity guard, posts plan to Slack. Idempotent — tracks finalization state via tags.
---

# PM Sprint Planner

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Capacity guard: max $SPRINT_BUDGET_SP SP / 25 tasks — blocks if exceeded
- Idempotency: `sprint-finalized-YYYY-MM-DD` tag prevents re-processing
- No auto-create sprints — must exist in ClickUp already
- Never delete tasks
- Sprint mix target: $SPRINT_MIX
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | Candidates: $LIST_SPRINT_CANDIDATES | Budget: $SPRINT_BUDGET_SP SP"
```

---

## EXECUTION

### Step 1: Check Sprint State → /tmp/sprint-state.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '[.lists[] | select(.status.status != "done")] | sort_by(.date_created) | last | {id, name, status: .status.status, start_date, due_date}' \
  > /tmp/sprint-state.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-state.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-state.json)
echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"

[ -z "$SPRINT_ID" ] && echo "NO SPRINT FOUND — create one in ClickUp first" && exit 0
```

### Step 2: Check if Sprint Has Tasks (active vs empty)

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)

TASK_COUNT=$(cu_api GET "list/$SPRINT_ID/task?subtasks=true" | jq '.tasks | length')
echo "Sprint tasks: $TASK_COUNT"
```

If `TASK_COUNT > 0` → sprint is active, go to **Step 2a** (report only).
If `TASK_COUNT == 0` → sprint is empty, go to **Step 3** (check candidates).

### Step 2a: Active Sprint — Report Only (read-only)

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
DUE=$(jq -r '.due_date // empty' /tmp/sprint-state.json)
[ -n "$DUE" ] && DUE_FMT=$(date -d @$((DUE/1000)) +%Y-%m-%d 2>/dev/null || echo "$DUE") || DUE_FMT="no due date"

CAND_COUNT=$(cu_api GET "list/$LIST_SPRINT_CANDIDATES/task?subtasks=true" | jq '.tasks | length')

echo "Active sprint: $SPRINT_NAME (due $DUE_FMT)"
echo "Sprint candidates queued: $CAND_COUNT"
```

Post status to Slack `$SLACK_SPRINT`: `*{sprint_name}* — Active until {due}. {n} candidates queued.` **STOP.**

### Step 3: Fetch Candidates → /tmp/candidates.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
FINALIZE_TAG="sprint-finalized-$(date +%Y-%m-%d)"

cu_api GET "list/$LIST_SPRINT_CANDIDATES/task?subtasks=true" \
  | jq --arg cf "$SP_FIELD_ID" \
    '[.tasks[] | {
      id, name: .name[0:60],
      assignees: ([.assignees[].username]|join(",")),
      pri: (.priority.priority // "4"),
      sp: ((.custom_fields[] | select(.id==$cf) | .value) // 0),
      tags: [.tags[].name]
    }]' > /tmp/candidates.json

CAND_COUNT=$(jq length /tmp/candidates.json)
TOTAL_SP=$(jq '[.[].sp // 0]|add // 0' /tmp/candidates.json)

echo "Candidates: $CAND_COUNT tasks, $TOTAL_SP SP"

[ "$CAND_COUNT" -eq 0 ] && echo "No candidates — team needs to add tasks" && exit 0

# Idempotency check
ALREADY=$(jq --arg t "$FINALIZE_TAG" '[.[]|select(.tags|any(.==$t))]|length' /tmp/candidates.json)
[ "$ALREADY" -gt 0 ] && echo "Already finalized today ($ALREADY tagged) — stopping" && exit 0
```

### Step 4: Capacity + Mix Check

```bash
source ~/.claude/skills/_pm-shared/context.sh
CAND_COUNT=$(jq length /tmp/candidates.json)
TOTAL_SP=$(jq '[.[].sp // 0]|add // 0' /tmp/candidates.json)

# Count by type for mix check
BUGS=$(jq '[.[]|select(.tags|any(test("bug";"i")))]|length' /tmp/candidates.json)
FEATURES=$(jq '[.[]|select(.tags|any(test("feature|enhancement";"i")))]|length' /tmp/candidates.json)
COMPLIANCE=$(jq '[.[]|select(.tags|any(test("compliance|security";"i")))]|length' /tmp/candidates.json)

echo "Capacity check: $CAND_COUNT tasks (max 25), $TOTAL_SP SP (max $SPRINT_BUDGET_SP)"
echo "Mix: $BUGS bugs, $FEATURES features, $COMPLIANCE compliance"
echo "Target: $SPRINT_MIX"

if [ "$CAND_COUNT" -gt 25 ] || [ "$TOTAL_SP" -gt "$SPRINT_BUDGET_SP" ]; then
  echo "BLOCKED — over capacity"
  jq -r '.[]|"\(.name) → \(.sp)SP [\(.assignees)]"' /tmp/candidates.json
  echo "Remove candidates to get under limits, then run again."
  # Post warning to Slack and STOP
  exit 1
fi

if [ "$FEATURES" -lt "$SPRINT_MIN_FEATURES" ]; then
  echo "WARNING: Only $FEATURES features (min $SPRINT_MIN_FEATURES). Consider adding more."
fi

if [ "$COMPLIANCE" -gt "$SPRINT_MAX_COMPLIANCE" ]; then
  echo "WARNING: $COMPLIANCE compliance tasks (max $SPRINT_MAX_COMPLIANCE). Consider deferring some."
fi

echo "Under capacity — proceeding"
```

### Step 5: Move Candidates to Sprint → /tmp/finalize-log.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)
FINALIZE_TAG="sprint-finalized-$(date +%Y-%m-%d)"
> /tmp/finalize-log.txt

for row in $(jq -r '.[]|@base64' /tmp/candidates.json); do
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  SP=$(echo "$row"|base64 -d|jq -r '.sp')

  # Move to sprint list
  cu_api POST "list/$SPRINT_ID/task/$ID" > /dev/null

  # Tag for idempotency
  curl -s -X POST "https://api.clickup.com/api/v2/task/$ID/tag/$FINALIZE_TAG" \
    -H "Authorization: $CLICKUP_PERSONAL_TOKEN" > /dev/null

  echo "MOVED: $NAME (${SP}SP)" >> /tmp/finalize-log.txt
  sleep 0.3
done

cat /tmp/finalize-log.txt
```

### Step 6: Build Report → /tmp/sprint-plan.md

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
CAND_COUNT=$(jq length /tmp/candidates.json)
TOTAL_SP=$(jq '[.[].sp // 0]|add // 0' /tmp/candidates.json)
BUGS=$(jq '[.[]|select(.tags|any(test("bug";"i")))]|length' /tmp/candidates.json)
FEATURES=$(jq '[.[]|select(.tags|any(test("feature|enhancement";"i")))]|length' /tmp/candidates.json)
COMPLIANCE=$(jq '[.[]|select(.tags|any(test("compliance|security";"i")))]|length' /tmp/candidates.json)
TASK_LIST=$(jq -r '.[]|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP` [pri \(.pri)]"' /tmp/candidates.json | head -25)

cat > /tmp/sprint-plan.md << PEOF
# Sprint Plan: $SPRINT_NAME

## Summary
- **Tasks:** $CAND_COUNT
- **Total SP:** $TOTAL_SP / $SPRINT_BUDGET_SP
- **Mix:** $BUGS bugs + $FEATURES features + $COMPLIANCE compliance
- **Finalized:** $(date +%Y-%m-%d)

## Tasks
$TASK_LIST
PEOF

cat /tmp/sprint-plan.md
```

### Step 7: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
BODY=$(cat /tmp/sprint-plan.md | tail -n +3)  # skip markdown title
slack_post "$SLACK_SPRINT" "Sprint Plan: $SPRINT_NAME" "$BODY" "pm-sprint-planner"
```
