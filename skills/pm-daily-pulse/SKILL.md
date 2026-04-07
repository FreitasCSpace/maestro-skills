---
name: pm-daily-pulse
description: Daily sprint standup digest — fetches sprint tasks from ClickUp, groups by assignee, checks stale/blocked, posts standup-ready digest to Slack. Idempotent — updates existing message.
---

# PM Daily Pulse

**Fully autonomous. Read-only on ClickUp. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Read-only on ClickUp — NEVER creates, updates, or deletes tasks
- Idempotent Slack posts — updates existing digest if already posted today
- No sprint → write /tmp/no-sprint sentinel and skip remaining steps (do NOT exit)
- **ALL API responses go to /tmp files. Only read summaries into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | SP field: $SP_FIELD_ID"
rm -f /tmp/no-sprint   # clear sentinel from prior run
```

---

## EXECUTION

### Step 1: Find Active Sprint → /tmp/sprint-info.json

Active sprint = a list in FOLDER_SPRINTS whose `start_date <= now < due_date`.
Falls back to the most recently started non-done list if no exact date match.

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select(
            (.start_date // "0" | tonumber) <= $now
            and ((.due_date // "9999999999999" | tonumber) > $now)
          )
      ]
      | sort_by(.start_date // "0" | tonumber)
      | last
      // (
          # fallback: latest-started non-done list
          [ .lists[] | select(.status.status != "done") ]
          | sort_by(.start_date // "0" | tonumber)
          | last
        )
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' \
  > /tmp/sprint-info.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-info.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-info.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO ACTIVE SPRINT — skipping digest"
  touch /tmp/no-sprint
  slack_post "$SLACK_STANDUP" "Daily Pulse — $(date +%Y-%m-%d)" \
    "No active sprint found. Digest skipped." "pm-daily-pulse"
else
  echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"
fi
```

### Step 2: Fetch Sprint Tasks → /tmp/sprint-tasks.json

Paginated. SP stored as number. Uses `date_updated` (not comments) for staleness.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-info.json)

> /tmp/sprint-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/sprint-page.json
  COUNT=$(jq '.tasks | length' /tmp/sprint-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/sprint-page.json >> /tmp/sprint-pages.ndjson
  echo >> /tmp/sprint-pages.ndjson
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
      updated_ms: (.date_updated // "0" | tonumber),
      url
    }
  ]' /tmp/sprint-pages.ndjson > /tmp/sprint-tasks.json

echo "Sprint tasks: $(jq length /tmp/sprint-tasks.json)"
[ "$(jq length /tmp/sprint-tasks.json)" = "0" ] && \
  echo "WARNING: sprint exists but has 0 tasks — check ClickUp configuration"
```

### Step 3: Stale Check + Open PRs

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

NOW_MS=$(( $(date +%s) * 1000 ))
STALE_MS=$(( STALE_TASK_DAYS * 86400 * 1000 ))

# Stale = not done/closed, and date_updated older than STALE_TASK_DAYS
jq -r --argjson now "$NOW_MS" --argjson stale "$STALE_MS" '
  .[] | select(.status | test("complete|done|closed|resolved") | not)
      | select(($now - .updated_ms) > $stale)
      | { name, assignees, updated_ms,
          days: ((($now - .updated_ms) / 86400000) | floor) }
      | "\(.days)d\t\(.name[0:60])\t\(.assignees|join(","))"
' /tmp/sprint-tasks.json > /tmp/stale-tasks.tsv 2>/dev/null

echo "Stale tasks: $(wc -l < /tmp/stale-tasks.tsv)"

# Open PRs across CI repos
> /tmp/open-prs.txt
for repo in $CI_REPOS; do
  gh pr list --repo "$GITHUB_ORG/$repo" --state open \
    --json number,title,author --limit 20 2>/dev/null \
    | jq -r --arg r "$repo" \
        '.[] | "\($r)#\(.number)\t\(.title[0:55])\t@\(.author.login)"' \
    >> /tmp/open-prs.txt
done
echo "Open PRs: $(wc -l < /tmp/open-prs.txt)"
```

### Step 4: Build Standup Digest → /tmp/sprint-health.md

Groups tasks by assignee. Each person gets a single-glance status summary.
Format is designed to be read aloud in standup or scrolled on mobile.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-info.json)
START_MS=$(jq -r '.start_ms' /tmp/sprint-info.json)
NOW_MS=$(( $(date +%s) * 1000 ))
NOW_S=$(date +%s)

# ── Sprint health math ───────────────────────────────────────────────
TOTAL=$(jq 'length' /tmp/sprint-tasks.json)
DONE=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))]|length'  /tmp/sprint-tasks.json)
IN_P=$(jq  '[.[]|select(.status|test("in progress|review|in review|active"))]|length' /tmp/sprint-tasks.json)
BLKD=$(jq  '[.[]|select(.status|test("blocked|waiting"))]|length'                     /tmp/sprint-tasks.json)
TODO=$(jq  '[.[]|select(.status|test("to do|open|pending|backlog|new"))]|length'       /tmp/sprint-tasks.json)

TOTAL_SP=$(jq '[.[].sp] | add // 0'                                                         /tmp/sprint-tasks.json)
DONE_SP=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))|.sp]|add // 0'    /tmp/sprint-tasks.json)
REMAIN_SP=$(( TOTAL_SP - DONE_SP ))

[ "$TOTAL_SP" -gt 0 ] && COMPLETION=$(( DONE_SP * 100 / TOTAL_SP )) || COMPLETION=0

# Time progress
START_S=$(( START_MS / 1000 ))
DUE_S=$(( DUE_MS / 1000 ))
DURATION_S=$(( DUE_S - START_S ))
if [ "$DURATION_S" -gt 0 ]; then
  ELAPSED_S=$(( NOW_S - START_S ))
  TIME_PCT=$(( ELAPSED_S * 100 / DURATION_S ))
  [ "$TIME_PCT" -lt 0 ] && TIME_PCT=0
  [ "$TIME_PCT" -gt 100 ] && TIME_PCT=100
  DAYS_LEFT=$(( (DUE_S - NOW_S) / 86400 ))
  [ "$DAYS_LEFT" -lt 0 ] && DAYS_LEFT=0
  DUE_FMT=$(date -d "@$DUE_S" +%b\ %d 2>/dev/null || echo "?")
else
  TIME_PCT=50; DAYS_LEFT="?"; DUE_FMT="no due date"
fi

# Health: on-track if completion within 10% of time elapsed
THRESHOLD=$(( TIME_PCT - 10 ))
[ "$THRESHOLD" -lt 0 ] && THRESHOLD=0
if   [ "$COMPLETION" -ge "$THRESHOLD" ];        then HEALTH="On Track"; EMOJI="🟢"
elif [ "$COMPLETION" -ge $(( THRESHOLD - 15 )) ]; then HEALTH="At Risk";  EMOJI="🟡"
else HEALTH="Behind";   EMOJI="🔴"; fi

STALE_COUNT=$(wc -l < /tmp/stale-tasks.tsv)
PR_COUNT=$(wc -l < /tmp/open-prs.txt)
UNASSIGNED=$(jq '[.[]|select(.assignees|length==0)]|length' /tmp/sprint-tasks.json)

# ── Assignee grouping ────────────────────────────────────────────────
# Extract all unique assignees + "unassigned" bucket
jq -r '
  [ .[] | if (.assignees|length)==0 then "unassigned" else .assignees[] end ]
  | unique | .[]
' /tmp/sprint-tasks.json > /tmp/assignees.txt

> /tmp/by-assignee.md

while IFS= read -r person; do
  # Tasks for this person (by assignee or unassigned bucket)
  if [ "$person" = "unassigned" ]; then
    PERSON_TASKS=$(jq -r '[.[]|select(.assignees|length==0)]' /tmp/sprint-tasks.json)
  else
    PERSON_TASKS=$(jq -r --arg p "$person" '[.[]|select(.assignees|contains([$p]))]' /tmp/sprint-tasks.json)
  fi

  P_DONE=$(echo "$PERSON_TASKS" | jq '[.[]|select(.status|test("complete|done|closed|resolved"))]|length')
  P_INP=$(echo  "$PERSON_TASKS" | jq '[.[]|select(.status|test("in progress|review|in review|active"))]|length')
  P_BLKD=$(echo "$PERSON_TASKS" | jq '[.[]|select(.status|test("blocked|waiting"))]|length')
  P_TODO=$(echo "$PERSON_TASKS" | jq '[.[]|select(.status|test("to do|open|pending|backlog|new"))]|length')
  P_SP_DONE=$(echo "$PERSON_TASKS" | jq '[.[]|select(.status|test("complete|done|closed|resolved"))|.sp]|add//0')
  P_SP_TOTAL=$(echo "$PERSON_TASKS" | jq '[.[].sp]|add//0')

  # Person header
  if [ "$person" = "unassigned" ]; then
    HEADER="*⚠️ Unassigned* — $P_TODO tasks need an owner"
  else
    HEADER="*@${person}* — ${P_DONE} done · ${P_INP} in progress · ${P_BLKD} blocked · ${P_TODO} to do | ${P_SP_DONE}/${P_SP_TOTAL} SP"
  fi

  {
    echo "$HEADER"
    # Done
    echo "$PERSON_TASKS" | jq -r '.[]|select(.status|test("complete|done|closed|resolved"))|"  ✅ \(.name) _(\(.sp)SP)_"'
    # In progress
    echo "$PERSON_TASKS" | jq -r '.[]|select(.status|test("in progress|review|in review|active"))|"  🔄 \(.name) _(\(.sp)SP)_"'
    # Blocked
    echo "$PERSON_TASKS" | jq -r '.[]|select(.status|test("blocked|waiting"))|"  🚫 \(.name) _(\(.sp)SP)_"'
    # To do (cap at 3 per person to keep digest scannable)
    echo "$PERSON_TASKS" | jq -r '.[]|select(.status|test("to do|open|pending|backlog|new"))|"  📋 \(.name) _(\(.sp)SP)_"' | head -3
    P_TODO_EXTRA=$(( P_TODO - 3 ))
    [ "$P_TODO_EXTRA" -gt 0 ] && echo "  _…and $P_TODO_EXTRA more_"
    echo ""
  } >> /tmp/by-assignee.md

done < /tmp/assignees.txt

# ── Stale tasks summary ──────────────────────────────────────────────
STALE_LINES=""
[ "$STALE_COUNT" -gt 0 ] && \
  STALE_LINES=$(awk -F'\t' '{printf "  ⏱ %sd — %s (%s)\n", $1, $2, $3}' /tmp/stale-tasks.tsv | head -5)

# ── Open PRs summary ────────────────────────────────────────────────
PR_LINES=""
[ "$PR_COUNT" -gt 0 ] && \
  PR_LINES=$(awk -F'\t' '{printf "  🔗 %s — %s %s\n", $1, $2, $3}' /tmp/open-prs.txt | head -5)

# ── Compose final digest ─────────────────────────────────────────────
cat > /tmp/sprint-health.md << HEOF
# Sprint Digest — $(date +"%B %d, %Y")

${EMOJI} *${HEALTH}* — ${SPRINT_NAME}
✅ ${DONE}/${TOTAL} done (${DONE_SP}/${TOTAL_SP} SP) | 🔄 ${IN_P} in progress | 🚫 ${BLKD} blocked | 📋 ${TODO} to do | ⏳ ${DAYS_LEFT}d left (${DUE_FMT}) | Time elapsed: ${TIME_PCT}%

━━━━━━━━━━━━━━━━━━━━━
$(cat /tmp/by-assignee.md)
━━━━━━━━━━━━━━━━━━━━━
$([ "$STALE_COUNT" -gt 0 ] && echo "*Stale (>${STALE_TASK_DAYS}d no activity)*" && echo "$STALE_LINES")
$([ "$PR_COUNT"    -gt 0 ] && echo "*Open PRs*" && echo "$PR_LINES")
HEOF

cat /tmp/sprint-health.md
```

### Step 5: Post to Slack (idempotent)

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
BODY=$(tail -n +3 /tmp/sprint-health.md)   # skip markdown title line
slack_post "$SLACK_STANDUP" "Daily Pulse — $SPRINT_NAME — $(date +%Y-%m-%d)" "$BODY" "pm-daily-pulse"
```
