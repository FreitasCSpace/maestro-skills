---
name: pm-retrospective
description: End-of-sprint retrospective — calculates velocity (SP-based), moves carryovers to Sprint Candidates with priority bump, posts retro summary to Slack. Idempotent — uses sprint-id tag to prevent double-processing.
---

# PM Retrospective

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_SPRINT, $SLACK_STANDUP, $SLACK_ENGINEERING). If channel not found, FAIL — NEVER substitute. NEVER post to #carespace-team, #general, #eng-general.
- Only runs if sprint is PAST due date — sentinel skip if still active
- Idempotency: `retro-{sprint-id}` tag on tasks prevents re-processing (sprint-id, not date)
- Max 15 carryovers — posts Slack alert and STOPS if exceeded
- Never delete tasks. Priority bump capped at 2 (High) unless task has security/compliance tag
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | Candidates: $LIST_SPRINT_CANDIDATES | SP field: $SP_FIELD_ID"
rm -f /tmp/retro-skip   # clear sentinel from prior run
```

---

## EXECUTION

### Step 1: Find Ended Sprint + Guard Checks → /tmp/retro-sprint.json

Target sprint = the one whose due_date <= now and is closest to now (most recently ended non-done sprint).
Writes /tmp/retro-skip sentinel if no eligible sprint — downstream steps check and return early.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select((.due_date // "0" | tonumber) > 0)
        | select((.due_date | tonumber) <= $now)
      ]
      | sort_by(.due_date | tonumber)
      | last
      | {id, name, status: .status.status,
         due_ms: (.due_date | tonumber),
         start_ms: (.start_date // "0" | tonumber)}
    ' > /tmp/retro-sprint.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/retro-sprint.json)
SPRINT_NAME=$(jq -r '.name // "unknown"' /tmp/retro-sprint.json)
RETRO_TAG="retro-${SPRINT_ID}"

if [ -z "$SPRINT_ID" ]; then
  echo "No ended sprint found — skipping"
  touch /tmp/retro-skip; return 0
fi

echo "Sprint ended: $SPRINT_NAME (id: $SPRINT_ID, tag: $RETRO_TAG)"
```

### Step 2: Fetch Tasks + Idempotency Check → /tmp/retro-tasks.json

Paginated. SP stored as number. Idempotency tag is `retro-{sprint-id}` — stable across re-runs on different days.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/retro-sprint.json)
RETRO_TAG="retro-${SPRINT_ID}"

> /tmp/retro-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/retro-page.json
  COUNT=$(jq '.tasks | length' /tmp/retro-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/retro-page.json >> /tmp/retro-pages.ndjson
  echo >> /tmp/retro-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:70],
      status: (.status.status | ascii_downcase),
      assignees: [.assignees[].username],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      tags: [.tags[].name]
    }
  ]' /tmp/retro-pages.ndjson > /tmp/retro-tasks.json

TOTAL=$(jq length /tmp/retro-tasks.json)
echo "Total tasks: $TOTAL"

if [ "$TOTAL" -eq 0 ]; then
  echo "Empty sprint — skipping"
  touch /tmp/retro-skip; return 0
fi

# Idempotency: check for retro-{sprint-id} tag on any task
ALREADY=$(jq --arg t "$RETRO_TAG" '[.[] | select(.tags | any(. == $t))] | length' /tmp/retro-tasks.json)
if [ "$ALREADY" -gt 0 ]; then
  echo "Retro already ran for sprint $SPRINT_ID ($ALREADY tasks tagged) — skipping"
  touch /tmp/retro-skip; return 0
fi
echo "No retro tag found — proceeding"
```

### Step 3: Calculate Metrics → /tmp/retro-report.md

Health and completion based on **SP delivered**, not task count.
Carryover safety check runs here — if exceeded, posts Slack alert and sets skip sentinel.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
SPRINT_ID=$(jq -r '.id' /tmp/retro-sprint.json)

TOTAL=$(jq 'length' /tmp/retro-tasks.json)
DONE=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))]|length'  /tmp/retro-tasks.json)
CARRY=$(jq '[.[]|select(.status|test("complete|done|closed|resolved")|not)]|length' /tmp/retro-tasks.json)

TOTAL_SP=$(jq '[.[].sp]       | add // 0' /tmp/retro-tasks.json)
DONE_SP=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))|.sp] | add // 0' /tmp/retro-tasks.json)

[ "$TOTAL_SP" -gt 0 ] && COMPLETION=$(( DONE_SP * 100 / TOTAL_SP )) || COMPLETION=0

if   [ "$COMPLETION" -ge 80 ]; then HEALTH="Healthy";  EMOJI="🟢"
elif [ "$COMPLETION" -ge 60 ]; then HEALTH="At Risk";  EMOJI="🟡"
else                                 HEALTH="Underrun"; EMOJI="🔴"; fi

# Carryover safety check — alert + stop before touching anything
if [ "$CARRY" -gt 15 ]; then
  MSG="⚠️ *Retro blocked for $SPRINT_NAME* — $CARRY carryovers exceeds limit (15). Manual review required before moving tasks."
  slack_post "$SLACK_SPRINT" "Retro Blocked: $SPRINT_NAME" "$MSG" "pm-retrospective"
  echo "BLOCKED: $CARRY carryovers > 15. Slack alert posted. Stopping."
  touch /tmp/retro-skip; return 0
fi

DONE_LIST=$(jq -r '
  .[] | select(.status | test("complete|done|closed|resolved"))
      | "• *\(.name)* — _\(.assignees|join(", "))_ `\(.sp)SP`"
' /tmp/retro-tasks.json | head -20)

CARRY_LIST=$(jq -r '
  .[] | select(.status | test("complete|done|closed|resolved") | not)
      | "• *\(.name)* — _\(.assignees|join(", "))_ `\(.sp)SP` [pri \(.pri)]"
' /tmp/retro-tasks.json | head -20)

{
  printf '# Sprint Retro: %s\n\n' "$SPRINT_NAME"
  printf '## %s %s — %d%% complete (%d/%d SP)\n' "$EMOJI" "$HEALTH" "$COMPLETION" "$DONE_SP" "$TOTAL_SP"
  printf '- **Tasks:** %d/%d done | **Carryovers:** %d\n' "$DONE" "$TOTAL" "$CARRY"
  printf '- **Velocity:** %d SP delivered (budget: %d SP)\n\n' "$DONE_SP" "$SPRINT_BUDGET_SP"
  printf '## Done\n%s\n\n' "${DONE_LIST:-_None — odd sprint!_}"
  printf '## Carried Over\n%s\n' "${CARRY_LIST:-_None — perfect sprint!_}"
} > /tmp/retro-report.md

cat /tmp/retro-report.md
```

### Step 4: Move Carryovers + Tag All Tasks

Links carryovers to Sprint Candidates list (task remains visible in both sprint and candidates).
Priority bump capped at 2 (High) — security/compliance tagged tasks may go to 1 (Urgent).
All tasks (done + carryover) tagged `retro-{sprint-id}` via `cu_api` for reliable retry logic.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

RETRO_TAG="retro-$(jq -r '.id' /tmp/retro-sprint.json)"
SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
> /tmp/retro-move-log.txt

# ── Move carryovers to Sprint Candidates ─────────────────────────────
jq -r '.[] | select(.status | test("complete|done|closed|resolved") | not) | @base64' \
  /tmp/retro-tasks.json \
| while IFS= read -r row; do
  ID=$(echo "$row"   | base64 -d | jq -r '.id')
  NAME=$(echo "$row" | base64 -d | jq -r '.name')
  PRI=$(echo "$row"  | base64 -d | jq -r '.pri')
  TAGS=$(echo "$row" | base64 -d | jq -r '.tags | join(",")')

  # Priority bump: cap at 2 (High) unless security/compliance — then allow 1 (Urgent)
  case "$PRI" in
    4) NEWPRI=3 ;;
    3) NEWPRI=2 ;;
    2) echo "$TAGS" | grep -qiE "security|compliance" && NEWPRI=1 || NEWPRI=2 ;;
    *) NEWPRI=$PRI ;;
  esac

  # Link task to Sprint Candidates list
  cu_api POST "list/$LIST_SPRINT_CANDIDATES/task/$ID" '{}' > /dev/null

  # Update priority
  cu_api PUT "task/$ID" "{\"priority\":$NEWPRI}" > /dev/null

  # Add carryover tag via cu_api (respects retry logic)
  cu_api POST "task/$ID/tag/carryover" '{}' > /dev/null

  # Comment on task
  COMMENT=$(jq -n --arg sprint "$SPRINT_NAME" --arg op "$PRI" --arg np "$NEWPRI" --arg date "$(date +%Y-%m-%d)" \
    '{comment_text: "Carried over from \($sprint). Priority bumped \($op)→\($np). — PM Bot \($date)"}')
  cu_api POST "task/$ID/comment" "$COMMENT" > /dev/null

  echo "MOVED: $NAME (pri $PRI→$NEWPRI)" >> /tmp/retro-move-log.txt
  sleep 0.3
done

# ── Tag all tasks with retro-{sprint-id} for idempotency ─────────────
# Only tag open tasks — closed tasks may be locked in ClickUp
jq -r '.[] | select(.status | test("complete|done|closed|resolved") | not) | .id' \
  /tmp/retro-tasks.json \
| while IFS= read -r task_id; do
  cu_api POST "task/$task_id/tag/$RETRO_TAG" '{}' > /dev/null
  sleep 0.1
done

echo "=== Carryover Summary ===" >> /tmp/retro-move-log.txt
cat /tmp/retro-move-log.txt
```

### Step 5: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
BODY=$(tail -n +3 /tmp/retro-report.md)   # skip markdown title
slack_post "$SLACK_SPRINT" "Sprint Retro: $SPRINT_NAME" "$BODY" "pm-retrospective"
```
