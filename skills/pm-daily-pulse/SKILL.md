---
name: pm-daily-pulse
description: Daily sprint standup digest — fetches sprint tasks from ClickUp, checks stale tasks, matches PRs, calculates health, posts to Slack. Idempotent — updates existing message.
---

# PM Daily Pulse

**Fully autonomous. Read-only on ClickUp. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Read-only on ClickUp — NEVER creates, updates, or deletes tasks
- Idempotent Slack posts — updates existing digest if already posted today
- No sprint = no post (single skip message)
- **ALL API responses go to /tmp files. Only read summaries into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | SP field: $SP_FIELD_ID"
```

---

## EXECUTION

### Step 1: Find Active Sprint → /tmp/sprint-info.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '[.lists[] | select(.status.status != "done")] | sort_by(.date_created) | last | {id, name, status: .status.status, start_date, due_date}' \
  > /tmp/sprint-info.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-info.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-info.json)
echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"

[ -z "$SPRINT_ID" ] && echo "NO ACTIVE SPRINT — stopping" && exit 0
```

If no sprint, post "No active sprint. Digest skipped." to `$SLACK_STANDUP` and **stop**.

### Step 2: Fetch Sprint Tasks → /tmp/sprint-tasks.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sprint-info.json)

cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true" \
  | jq --arg cf "$SP_FIELD_ID" \
    '[.tasks[] | {
      id, name: .name[0:60],
      status: .status.status,
      assignees: ([.assignees[].username] | join(",")),
      pri: (.priority.priority // "4"),
      sp: ((.custom_fields[] | select(.id==$cf) | .value) // 0),
      last_comment_ts: ((.comments // [])[0].date // 0),
      url
    }]' > /tmp/sprint-tasks.json

echo "Sprint tasks: $(jq length /tmp/sprint-tasks.json)"
```

### Step 3: Check for Stale Tasks + PR Matches → /tmp/stale-tasks.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW=$(date +%s)
STALE_SECS=$((STALE_TASK_DAYS * 86400))
> /tmp/stale-tasks.txt

# Check for open PRs in CI repos
> /tmp/open-prs.txt
for repo in $CI_REPOS; do
  gh pr list --repo $GITHUB_ORG/$repo --state open --json number,title,author --limit 20 2>/dev/null \
    | jq -r --arg r "$repo" '.[] | "\($r)#\(.number) \(.title[0:60]) (@\(.author.login))"' \
    >> /tmp/open-prs.txt
done

echo "Open PRs: $(wc -l < /tmp/open-prs.txt)"

# Find stale tasks (not done, no comments in STALE_TASK_DAYS days)
jq -r --argjson now "$NOW" --argjson stale "$STALE_SECS" \
  '.[] | select(.status | test("complete|done|closed";"i") | not) | select((($now * 1000) - (.last_comment_ts | tonumber)) > ($stale * 1000)) | "STALE (\((($now * 1000 - (.last_comment_ts | tonumber)) / 86400000) | floor)d): \(.name) → \(.assignees)"' \
  /tmp/sprint-tasks.json > /tmp/stale-tasks.txt 2>/dev/null

echo "Stale tasks: $(wc -l < /tmp/stale-tasks.txt)"
cat /tmp/stale-tasks.txt
```

### Step 4: Calculate Health → /tmp/sprint-health.md

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
DUE=$(jq -r '.due_date // empty' /tmp/sprint-info.json)
START=$(jq -r '.start_date // empty' /tmp/sprint-info.json)

TOTAL=$(jq length /tmp/sprint-tasks.json)
DONE=$(jq '[.[]|select(.status|test("complete|done|closed|resolved";"i"))]|length' /tmp/sprint-tasks.json)
IN_PROGRESS=$(jq '[.[]|select(.status|test("in progress|active|review";"i"))]|length' /tmp/sprint-tasks.json)
TOTAL_SP=$(jq '[.[].sp // 0]|add // 0' /tmp/sprint-tasks.json)
DONE_SP=$(jq '[.[]|select(.status|test("complete|done|closed|resolved";"i"))|.sp // 0]|add // 0' /tmp/sprint-tasks.json)

if [ "$TOTAL_SP" -gt 0 ]; then
  COMPLETION=$((DONE_SP * 100 / TOTAL_SP))
else
  COMPLETION=0
fi

# Time elapsed calculation
if [ -n "$START" ] && [ -n "$DUE" ]; then
  NOW=$(date +%s)
  START_S=$((START / 1000))
  DUE_S=$((DUE / 1000))
  DURATION=$((DUE_S - START_S))
  ELAPSED=$((NOW - START_S))
  [ "$DURATION" -gt 0 ] && TIME_PCT=$((ELAPSED * 100 / DURATION)) || TIME_PCT=0
  [ -n "$DUE" ] && DUE_FMT=$(date -d @$((DUE/1000)) +%Y-%m-%d 2>/dev/null || echo "$DUE") || DUE_FMT="no due date"
  DAYS_LEFT=$(( (DUE_S - NOW) / 86400 ))
else
  TIME_PCT=50; DUE_FMT="no due date"; DAYS_LEFT="?"
fi

# Health: compare completion % vs time elapsed %
if [ "$COMPLETION" -ge $((TIME_PCT - 5)) ]; then HEALTH="On Track"; EMOJI="🟢"
elif [ "$COMPLETION" -ge $((TIME_PCT - 15)) ]; then HEALTH="At Risk"; EMOJI="🟡"
else HEALTH="Behind"; EMOJI="🔴"; fi

# Burndown
REMAINING_SP=$((TOTAL_SP - DONE_SP))

# Task lists by status
DONE_LIST=$(jq -r '.[]|select(.status|test("complete|done|closed|resolved";"i"))|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP`"' /tmp/sprint-tasks.json | head -15)
PROGRESS_LIST=$(jq -r '.[]|select(.status|test("in progress|active|review";"i"))|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP`"' /tmp/sprint-tasks.json | head -15)
TODO_LIST=$(jq -r '.[]|select(.status|test("to do|pending|open|backlog";"i"))|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP`"' /tmp/sprint-tasks.json | head -15)
BLOCKED_LIST=$(jq -r '.[]|select(.status|test("blocked";"i"))|"• *\(.name)* → _\(.assignees)_ `\(.sp)SP`"' /tmp/sprint-tasks.json | head -10)

UNASSIGNED=$(jq '[.[]|select(.assignees=="")]|length' /tmp/sprint-tasks.json)
STALE_COUNT=$(wc -l < /tmp/stale-tasks.txt)
PR_COUNT=$(wc -l < /tmp/open-prs.txt)

cat > /tmp/sprint-health.md << HEOF
# Sprint Digest — $(date +"%B %d, %Y")

## $EMOJI $HEALTH — $SPRINT_NAME
- **Completion:** ${COMPLETION}% (${DONE_SP}/${TOTAL_SP} SP) | Budget: ${SPRINT_BUDGET_SP} SP
- **Tasks:** ${DONE}/${TOTAL} done | ${IN_PROGRESS} in progress
- **Burndown:** ${REMAINING_SP} SP remaining
- **Due:** $DUE_FMT ($DAYS_LEFT days left) | Time elapsed: ${TIME_PCT}%
- **Unassigned:** $UNASSIGNED | **Stale:** $STALE_COUNT | **Open PRs:** $PR_COUNT

## Done
${DONE_LIST:-_None yet_}

## In Progress
${PROGRESS_LIST:-_None_}

## To Do
${TODO_LIST:-_None_}

## Blocked
${BLOCKED_LIST:-_None_}

## Stale Tasks (>${STALE_TASK_DAYS}d no activity)
$(cat /tmp/stale-tasks.txt | head -5)

## Open PRs
$(cat /tmp/open-prs.txt | head -10)
HEOF

cat /tmp/sprint-health.md
```

### Step 5: Post to Slack (idempotent)

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
BODY=$(cat /tmp/sprint-health.md | tail -n +3)  # skip markdown title
slack_post "$SLACK_STANDUP" "Sprint Digest — $SPRINT_NAME" "$BODY" "pm-daily-pulse"
```
