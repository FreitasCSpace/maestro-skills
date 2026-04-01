---
name: pm-retrospective
description: End-of-sprint retrospective — calculates velocity, completion %, moves carryovers to Sprint Candidates with priority bump, posts retro summary to Slack. Idempotent — uses retro tag to prevent double-processing.
---

# PM Retrospective

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Only runs if sprint is PAST due date — silent skip if still active
- Idempotency: `retro-YYYY-MM-DD` tag on tasks prevents re-processing
- Max 15 carryovers — blocks and alerts Slack if exceeded
- Never delete tasks, never bump priority more than 1 level
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | Candidates: $LIST_SPRINT_CANDIDATES | SP field: $SP_FIELD_ID"
```

---

## EXECUTION

### Step 1: Find Sprint + Guard Checks → /tmp/retro-sprint.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
RETRO_TAG="retro-$(date +%Y-%m-%d)"
echo "Retro tag: $RETRO_TAG"

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '[.lists[] | select(.status.status != "done")] | sort_by(.date_created) | last | {id, name, status: .status.status, due_date}' \
  > /tmp/retro-sprint.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/retro-sprint.json)
SPRINT_NAME=$(jq -r '.name // "unknown"' /tmp/retro-sprint.json)
DUE=$(jq -r '.due_date // empty' /tmp/retro-sprint.json)
NOW_MS=$(($(date +%s) * 1000))

echo "Sprint: $SPRINT_NAME | Due: $DUE | Now: $NOW_MS"

[ -z "$SPRINT_ID" ] && echo "No sprint found — stopping" && exit 0
[ -n "$DUE" ] && [ "$NOW_MS" -lt "$DUE" ] && echo "Sprint still active — stopping" && exit 0
echo "Sprint ended — proceeding with retro"
```

### Step 2: Fetch Tasks + Idempotency Check → /tmp/retro-tasks.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/retro-sprint.json)

cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true" \
  | jq --arg cf "$SP_FIELD_ID" \
    '[.tasks[] | {
      id, name: .name[0:60],
      status: .status.status,
      assignees: ([.assignees[].username]|join(",")),
      pri: (.priority.priority // "4"),
      sp: ((.custom_fields[] | select(.id==$cf) | .value) // 0),
      tags: [.tags[].name]
    }]' > /tmp/retro-tasks.json

TOTAL=$(jq length /tmp/retro-tasks.json)
echo "Total tasks: $TOTAL"

[ "$TOTAL" -eq 0 ] && echo "Empty sprint — stopping" && exit 0

# Idempotency check
RETRO_TAG="retro-$(date +%Y-%m-%d)"
ALREADY=$(jq --arg t "$RETRO_TAG" '[.[] | select(.tags | any(. == $t))] | length' /tmp/retro-tasks.json)
[ "$ALREADY" -gt 0 ] && echo "Retro already ran today ($ALREADY tagged) — stopping" && exit 0
echo "No retro tag found — proceeding"
```

### Step 3: Calculate Metrics → /tmp/retro-report.md

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
TOTAL=$(jq length /tmp/retro-tasks.json)
DONE=$(jq '[.[]|select(.status|test("complete|done|closed|resolved";"i"))]|length' /tmp/retro-tasks.json)
CARRY=$((TOTAL - DONE))
TOTAL_SP=$(jq '[.[].sp // 0]|add // 0' /tmp/retro-tasks.json)
DONE_SP=$(jq '[.[]|select(.status|test("complete|done|closed|resolved";"i"))|.sp // 0]|add // 0' /tmp/retro-tasks.json)
[ "$TOTAL" -gt 0 ] && COMPLETION=$((DONE * 100 / TOTAL)) || COMPLETION=0

if [ "$COMPLETION" -ge 80 ]; then HEALTH="On Track"; EMOJI="🟢"
elif [ "$COMPLETION" -ge 60 ]; then HEALTH="At Risk"; EMOJI="🟡"
else HEALTH="Behind"; EMOJI="🔴"; fi

DONE_LIST=$(jq -r '.[]|select(.status|test("complete|done|closed|resolved";"i"))|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP`"' /tmp/retro-tasks.json | head -20)
CARRY_LIST=$(jq -r '.[]|select(.status|test("complete|done|closed|resolved";"i")|not)|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP` [pri \(.pri)]"' /tmp/retro-tasks.json | head -20)

cat > /tmp/retro-report.md << REOF
# Sprint Retro: $SPRINT_NAME

## $EMOJI $HEALTH — ${COMPLETION}% complete
- **Tasks:** ${DONE}/${TOTAL} done
- **Velocity:** ${DONE_SP} SP (budget: $SPRINT_BUDGET_SP SP)
- **Carryovers:** $CARRY tasks

## Done
${DONE_LIST:-_None_}

## Carried Over
${CARRY_LIST:-_None — perfect sprint!_}
REOF

echo "Carryovers: $CARRY (max 15)"
cat /tmp/retro-report.md
```

### Step 4: Safety Check + Move Carryovers

If carryovers > 15, post warning to Slack and **STOP**. Otherwise, move each incomplete task to Sprint Candidates, bump priority by 1, add `carryover` + `retro-YYYY-MM-DD` tags, add comment.

```bash
source ~/.claude/skills/_pm-shared/context.sh
CARRY=$(jq '[.[]|select(.status|test("complete|done|closed|resolved";"i")|not)]|length' /tmp/retro-tasks.json)
RETRO_TAG="retro-$(date +%Y-%m-%d)"
SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)

if [ "$CARRY" -gt 15 ]; then
  echo "BLOCKED: $CARRY carryovers exceeds limit (15)"
  # Post warning to Slack and stop
  exit 1
fi

> /tmp/retro-move-log.txt
for row in $(jq -r '.[]|select(.status|test("complete|done|closed|resolved";"i")|not)|@base64' /tmp/retro-tasks.json); do
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  PRI=$(echo "$row"|base64 -d|jq -r '.pri')

  # Bump priority (4→3, 3→2, 2→1, 1→1)
  case "$PRI" in 4) NEWPRI=3;; 3) NEWPRI=2;; 2) NEWPRI=1;; *) NEWPRI=$PRI;; esac

  # Move to candidates
  cu_api POST "list/$LIST_SPRINT_CANDIDATES/task/$ID" > /dev/null

  # Update priority
  cu_api PUT "task/$ID" "{\"priority\":$NEWPRI}" > /dev/null

  # Add tags
  curl -s -X POST "https://api.clickup.com/api/v2/task/$ID/tag/carryover" \
    -H "Authorization: $CLICKUP_PERSONAL_TOKEN" > /dev/null
  curl -s -X POST "https://api.clickup.com/api/v2/task/$ID/tag/$RETRO_TAG" \
    -H "Authorization: $CLICKUP_PERSONAL_TOKEN" > /dev/null

  # Comment
  cu_api POST "task/$ID/comment" "{\"comment_text\":\"Carried over from $SPRINT_NAME. Priority bumped $PRI→$NEWPRI. — PM Bot $(date +%Y-%m-%d)\"}" > /dev/null

  echo "MOVED: $NAME (pri $PRI→$NEWPRI)" >> /tmp/retro-move-log.txt
  sleep 0.3
done

# Tag done tasks too (for idempotency)
for row in $(jq -r '.[]|select(.status|test("complete|done|closed|resolved";"i"))|@base64' /tmp/retro-tasks.json); do
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  curl -s -X POST "https://api.clickup.com/api/v2/task/$ID/tag/$RETRO_TAG" \
    -H "Authorization: $CLICKUP_PERSONAL_TOKEN" > /dev/null
  sleep 0.1
done

cat /tmp/retro-move-log.txt
```

### Step 5: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
BODY=$(cat /tmp/retro-report.md | tail -n +3)  # skip markdown title
slack_post "$SLACK_SPRINT" "Sprint Retro: $SPRINT_NAME" "$BODY" "pm-retrospective"
```
