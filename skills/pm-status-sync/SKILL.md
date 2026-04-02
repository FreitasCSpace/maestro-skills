
---

## name: pm-status-sync
description: "Snoop Dogg" Slack bot that DMs team members for task status updates, syncs responses to ClickUp, creates missing tasks + GitHub issues, and updates the active sprint board. Solves the problem of people not updating ClickUp.

# PM Status Sync — "Snoop Dogg" Bot 🐕

Proactive status collection bot with a Snoop Dogg personality. Pings team members on Slack in Snoop's style, collects task updates, syncs everything back to ClickUp. Creates missing tasks and GitHub issues when new work is reported.

**Uses shared context from** `_pm-shared/context.sh`. Requires HITL approval for ClickUp writes and GitHub issue creation.

## BOT PERSONALITY — SNOOP DOGG 🎤

All Slack DM messages must be written in Snoop Dogg's voice:

* Use "fo shizzle", "ya dig", "what's crackalackin", "drop it like it's hot"
* Call people "cuz", "big homie", "playa"
* Keep it friendly, fun, and motivating — but still get the job done
* Use 🐕 🎵 🔥 💨 emojis liberally
* Sign off messages with variations like "— Snoop D-O-double-G, ya PM bot 🐕"
* When tasks are done: "That's straight fire, cuz! 🔥"
* When tasks are stale: "Yo cuz, these tasks been chillin longer than me on a Sunday 💨"
* When everything is on track: "Smooth like a G, baby 🎵"

## GUARDRAILS

* **Slack DMs are read+write** — sends proactive pings, reads replies
* **ClickUp is read+write** — updates task statuses, creates new tasks (HITL-gated)
* **GitHub is write** — creates issues for new work items (HITL-gated)
* **HITL required** before: creating ClickUp tasks, creating GitHub issues, changing task status
* **ALL API responses go to /tmp files. Only read summaries into context.**
* **Never remove or close tasks** — only update status forward (to do → in progress → review → done)
* **Respect quiet hours** — do not ping before 9am or after 6pm user's timezone
* **Idempotent pings** — tracks pings per day, never double-pings a user in the same day

## DAILY SCHEDULE (all times UTC)

Designed for a team across India, Portugal, Brazil, LATAM, and US timezones.
Scrum meeting at **4:30pm BST (15:30 UTC)**. Daily pulse at **4pm BST (15:00 UTC)**.

| UTC | BST | What | Who gets pinged |
|-----|-----|------|-----------------|
| 08:00 | 09:00 | **Wave 1** — run Steps 0–3 | India (1:30pm IST), Portugal (9am WEST) |
| 12:00 | 13:00 | **Wave 2** — run Steps 0–3 | Brazil (9am BRT), LATAM East |
| 13:00 | 14:00 | **Wave 3** — run Steps 0–3 | US East (9am EDT), LATAM West |
| 14:30 | 15:30 | **Reminder** — run Step 3.5 | Non-responders (all TZs) |
| 14:30 | 15:30 | **Wall of Shame** — run Step 3.6 | Non-responders posted to standup channel |
| 15:00 | 16:00 | **Daily Pulse** — run pm-daily-pulse | — |
| 15:00+ | 16:00+ | **Collect + Sync** — run Steps 4–9 | — |
| 15:30 | 16:30 | **Scrum meeting** | — |

Each wave re-runs Steps 0–3. Step 3 is idempotent — it skips users already pinged today and defers users outside work hours. Each wave naturally picks up users whose local time has entered the 9am–6pm window.

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | SP field: $SP_FIELD_ID"
echo "Slack standup: $SLACK_STANDUP"
```

## STEP 0.5: Build User Mappings → /tmp/clickup-users.json, /tmp/slack-users.json, /tmp/user-map.json

Auto-fetch ClickUp workspace members and Slack workspace users, then cross-reference by email to build the mapping.

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Fetch ClickUp team members
cu_api GET "team" | jq '[.teams[0].members[] | {
  cu_id: (.user.id | tostring),
  username: .user.username,
  email: .user.email,
  name: ((.user.first_name // "") + " " + (.user.last_name // "") | ltrimstr(" ") | rtrimstr(" "))
}]' > /tmp/clickup-users.json

echo "ClickUp users: $(jq length /tmp/clickup-users.json)"
jq -r '.[] | "\(.username) (\(.email)) — cu_id: \(.cu_id)"' /tmp/clickup-users.json

# Fetch Slack workspace members (including timezone info)
curl -s "https://slack.com/api/users.list?limit=200" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  | jq '[.members[] | select(.deleted == false and .is_bot == false and .id != "USLACKBOT") | {
    slack_id: .id,
    email: .profile.email,
    name: .real_name,
    display_name: .profile.display_name,
    tz: .tz,
    tz_label: .tz_label,
    tz_offset: .tz_offset
  }]' > /tmp/slack-users.json

echo "Slack users: $(jq length /tmp/slack-users.json)"

# Cross-reference by email → build unified map
jq -n --slurpfile cu /tmp/clickup-users.json --slurpfile sl /tmp/slack-users.json '
  [$cu[0][] | . as $cu_user |
    ($sl[0][] | select(.email == $cu_user.email)) as $sl_user |
    {
      username: $cu_user.username,
      email: $cu_user.email,
      name: $cu_user.name,
      cu_id: $cu_user.cu_id,
      slack_id: $sl_user.slack_id,
      slack_name: $sl_user.display_name,
      tz: $sl_user.tz,
      tz_label: $sl_user.tz_label,
      tz_offset: $sl_user.tz_offset
    }
  ]
' > /tmp/user-map.json

echo "Mapped users: $(jq length /tmp/user-map.json)"
jq -r '.[] | "\(.username): cu=\(.cu_id) slack=\(.slack_id) (\(.name))"' /tmp/user-map.json

# Also build the legacy format files the skill expects
jq 'map({(.username): .slack_id}) | add' /tmp/user-map.json > /tmp/slack-user-map.json
jq 'map({(.username): .cu_id}) | add' /tmp/user-map.json > /tmp/clickup-user-map.json
```


---

## EXECUTION

### Step 1: Find Active Sprint + Load Tasks → /tmp/sync-sprint.json, /tmp/sync-tasks.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Get active sprint
cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '[.lists[] | select(.status.status != "done")] | sort_by(.date_created) | last | {id, name, status: .status.status, start_date, due_date}' \
  > /tmp/sync-sprint.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sync-sprint.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sync-sprint.json)
echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"

[ -z "$SPRINT_ID" ] && echo "NO ACTIVE SPRINT — stopping" && exit 0

# Fetch all tasks in sprint
cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true" \
  | jq --arg cf "$SP_FIELD_ID" \
    '[.tasks[] | {
      id, name: .name[0:80],
      status: .status.status,
      assignees: ([.assignees[].username] | join(",")),
      assignee_ids: [.assignees[].id],
      pri: (.priority.priority // "4"),
      sp: ((.custom_fields[] | select(.id==$cf) | .value) // 0),
      last_comment_ts: ((.comments // [])[0].date // 0),
      date_updated: .date_updated,
      url
    }]' > /tmp/sync-tasks.json

echo "Sprint tasks: $(jq length /tmp/sync-tasks.json)"
```

### Step 2: Identify Stale/Unupdated Tasks Per User → /tmp/sync-stale-by-user.json

Skip users who already have at least one task "in progress" — they're actively working and don't need a ping.

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW=$(date +%s)
STALE_SECS=$((STALE_TASK_DAYS * 86400))

# Find users who have at least one "in progress" task — they don't need a ping
jq -r '[.[] | select(.status | test("in progress";"i"))] | [.[].assignees] | unique | .[]' \
  /tmp/sync-tasks.json > /tmp/sync-in-progress-users.txt

echo "Users with in-progress tasks (skipping):"
cat /tmp/sync-in-progress-users.txt

# Find tasks NOT done and not updated recently, group by assignee,
# then exclude users who have any "in progress" tasks
jq --argjson now "$NOW" --argjson stale_ms "$((STALE_SECS * 1000))" --slurpfile skip <(jq -Rs '[split("\n")[] | select(. != "")]' /tmp/sync-in-progress-users.txt) '
  [.[] |
    select(.status | test("complete|done|closed|resolved";"i") | not) |
    select(
      ((.date_updated // "0") | tonumber) < ($now * 1000 - $stale_ms)
    )
  ] |
  group_by(.assignees) |
  map({
    assignee: .[0].assignees,
    tasks: [.[] | {id, name, status, sp, url, days_stale: ((($now * 1000) - ((.date_updated // "0") | tonumber)) / 86400000 | floor)}]
  }) |
  [.[] | select(.assignee != "" and (.assignee as $a | $skip[0] | index($a) | not))]
' /tmp/sync-tasks.json > /tmp/sync-stale-by-user.json

echo "Users with stale tasks (after filtering): $(jq length /tmp/sync-stale-by-user.json)"
jq -r '.[] | "\(.assignee): \(.tasks | length) stale tasks"' /tmp/sync-stale-by-user.json
```

### Step 3: Ping Users on Slack (Snoop Style) → /tmp/sync-pings-sent.json

Timezone-aware, idempotent pings. Only pings users whose local time is within work hours (9am–6pm). Skips users already pinged today. Includes a deadline so they know when to reply by.

**Designed to be run multiple times per day in waves:**
- 08:00 UTC — Wave 1: India (IST) + Europe/Portugal (BST/WEST)
- 12:00 UTC — Wave 2: Brazil (BRT) + LATAM East
- 13:00 UTC — Wave 3: US East (EDT) + remaining LATAM
- 14:30 UTC — Reminder wave (Step 3.5) for non-responders

All waves feed the daily pulse generated at **15:00 UTC (4pm BST)**, 30 min before the **4:30pm BST scrum**.

```bash
source ~/.claude/skills/_pm-shared/context.sh

NOW_UTC=$(date -u +%s)
TODAY=$(date -u +%Y-%m-%d)
PING_LOG="/tmp/sync-pings-sent-${TODAY}.json"

# Response deadline: 3pm UTC (4pm BST) — daily pulse generation time
DEADLINE_UTC_H=15

# Initialize today's ping log if it doesn't exist (idempotency across waves)
if [ ! -f "$PING_LOG" ] || ! jq empty "$PING_LOG" 2>/dev/null; then
  echo "[]" > "$PING_LOG"
fi

ALREADY_PINGED=$(jq -r '.[].assignee' "$PING_LOG" 2>/dev/null)
echo "Already pinged today: $(echo "$ALREADY_PINGED" | grep -c . || echo 0)"

PINGS_THIS_WAVE='[]'

jq -c '.[]' /tmp/sync-stale-by-user.json | while read -r user_block; do
  ASSIGNEE=$(echo "$user_block" | jq -r '.assignee')
  TASK_COUNT=$(echo "$user_block" | jq '.tasks | length')

  # Skip if already pinged today
  if echo "$ALREADY_PINGED" | grep -qx "$ASSIGNEE"; then
    echo "SKIP: $ASSIGNEE already pinged today"
    continue
  fi

  # Look up Slack user ID + timezone from the user map
  SLACK_USER_ID=$(jq -r --arg user "$ASSIGNEE" '.[$user] // empty' /tmp/slack-user-map.json)

  if [ -z "$SLACK_USER_ID" ]; then
    echo "WARN: No Slack mapping for $ASSIGNEE — skipping"
    continue
  fi

  # Get user's timezone offset (seconds from UTC) from Slack profile
  TZ_OFFSET=$(jq -r --arg user "$ASSIGNEE" '.[] | select(.username == $user) | .tz_offset // 0' /tmp/user-map.json | head -1)
  TZ_LABEL=$(jq -r --arg user "$ASSIGNEE" '.[] | select(.username == $user) | .tz_label // "UTC"' /tmp/user-map.json | head -1)
  USER_LOCAL_HOUR=$(( (NOW_UTC + TZ_OFFSET) % 86400 / 3600 ))

  # Respect quiet hours — only ping between 9am and 6pm local time
  if [ "$USER_LOCAL_HOUR" -lt 9 ] || [ "$USER_LOCAL_HOUR" -ge 18 ]; then
    echo "DEFER: $ASSIGNEE — local time is ${USER_LOCAL_HOUR}:xx ($TZ_LABEL), outside 9am-6pm"
    continue
  fi

  # Calculate their local deadline time for the message
  DEADLINE_LOCAL_H=$(( (DEADLINE_UTC_H * 3600 + TZ_OFFSET) % 86400 / 3600 ))
  DEADLINE_LOCAL_STR="${DEADLINE_LOCAL_H}:00"
  # Handle afternoon display
  if [ "$DEADLINE_LOCAL_H" -gt 12 ]; then
    DEADLINE_DISPLAY="$((DEADLINE_LOCAL_H - 12)):00pm"
  elif [ "$DEADLINE_LOCAL_H" -eq 12 ]; then
    DEADLINE_DISPLAY="12:00pm"
  else
    DEADLINE_DISPLAY="${DEADLINE_LOCAL_H}:00am"
  fi

  # Build task list for the DM
  TASK_LIST=$(echo "$user_block" | jq -r '.tasks[] | "🎯 *\(.name)* (status: `\(.status)`, chillin for \(.days_stale)d) — \(.url)"')

  # Get user's first name for personalized greeting
  USER_NAME=$(jq -r --arg user "$ASSIGNEE" '.[] | select(.username == $user) | .name' /tmp/user-map.json | head -1)
  FIRST_NAME=$(echo "$USER_NAME" | awk '{print $1}')

  MSG="🐕 Yo what's crackalackin $FIRST_NAME! It's ya boy Snoop D-O-double-G, checkin in on yo sprint tasks, ya dig?\n\nLooks like these joints been sittin for a minute:\n\n${TASK_LIST}\n\n💬 *Drop me a reply with updates fo each task, cuz* — like:\n- \"TaskName: in progress, workin on the auth flow\"\n- \"TaskName: done, merged PR #42 — straight fire 🔥\"\n- \"New: started cookin up a caching layer (not in the sprint yet)\"\n\n⏰ *Need yo update by ${DEADLINE_DISPLAY} yo time* so I can cook up the pre-standup digest before our 4:30 scrum, ya dig?\n\nI'll sync everything to ClickUp fo ya, so you don't gotta lift a finger 💨\n\n— Snoop D-O-double-G, ya PM bot 🐕🎵"

  # Send DM via Slack API
  RESPONSE=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$SLACK_USER_ID" --arg txt "$MSG" '{channel: $ch, text: $txt, username: "Snoop Dogg 🐕", icon_emoji: ":dog:"}')")

  MSG_TS=$(echo "$RESPONSE" | jq -r '.ts // empty')
  CHANNEL=$(echo "$RESPONSE" | jq -r '.channel // empty')

  if [ -n "$MSG_TS" ]; then
    echo "Pinged $ASSIGNEE ($SLACK_USER_ID, $TZ_LABEL, local ${USER_LOCAL_HOUR}:xx) — ts: $MSG_TS"
    # Append to today's ping log
    jq --arg a "$ASSIGNEE" --arg sid "$SLACK_USER_ID" --arg ch "$CHANNEL" --arg ts "$MSG_TS" --argjson tc "$TASK_COUNT" --arg tz "$TZ_LABEL" \
      '. += [{"assignee": $a, "slack_user_id": $sid, "channel": $ch, "msg_ts": $ts, "task_count": $tc, "tz": $tz}]' \
      "$PING_LOG" > "${PING_LOG}.tmp" && mv "${PING_LOG}.tmp" "$PING_LOG"
  else
    echo "ERROR pinging $ASSIGNEE: $(echo "$RESPONSE" | jq -r '.error // "unknown"')"
  fi
done

# Symlink for downstream steps
cp "$PING_LOG" /tmp/sync-pings-sent.json

echo "Total pings today: $(jq length "$PING_LOG")"
jq -r '.[] | "\(.assignee) (\(.tz))"' "$PING_LOG"
```

### Step 3.5: Reminder Ping for Non-Responders (30 min before deadline)

Run at **14:30 UTC** (3:30pm BST). Checks who was pinged today but hasn't replied yet. Sends a Snoop-style nudge.

```bash
source ~/.claude/skills/_pm-shared/context.sh

TODAY=$(date -u +%Y-%m-%d)
PING_LOG="/tmp/sync-pings-sent-${TODAY}.json"

if [ ! -f "$PING_LOG" ] || [ "$(jq length "$PING_LOG")" -eq 0 ]; then
  echo "No pings sent today — nothing to remind"
  exit 0
fi

REMINDED=0

jq -c '.[]' "$PING_LOG" | while read -r ping; do
  CHANNEL=$(echo "$ping" | jq -r '.channel')
  MSG_TS=$(echo "$ping" | jq -r '.msg_ts')
  ASSIGNEE=$(echo "$ping" | jq -r '.assignee')
  SLACK_USER_ID=$(echo "$ping" | jq -r '.slack_user_id')

  # Check if they already replied
  REPLY_COUNT=$(curl -s "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$MSG_TS" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq '[.messages[1:][]] | length')

  if [ "$REPLY_COUNT" -gt 0 ]; then
    echo "$ASSIGNEE already replied — no reminder needed"
    continue
  fi

  # Get first name
  USER_NAME=$(jq -r --arg user "$ASSIGNEE" '.[] | select(.username == $user) | .name' /tmp/user-map.json | head -1)
  FIRST_NAME=$(echo "$USER_NAME" | awk '{print $1}')

  REMIND_MSG="🐕 Yo $FIRST_NAME! Quick reminder cuz — standup digest drops in 30 min and I ain't heard back from you yet 💨\n\nJust hit reply on my earlier message with yo task updates. Even a quick \"all good\" works, ya dig? 🎵\n\n— Snoop D-O-double-G 🐕"

  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$SLACK_USER_ID" --arg txt "$REMIND_MSG" --arg ts "$MSG_TS" '{channel: $ch, text: $txt, thread_ts: $ts, username: "Snoop Dogg 🐕", icon_emoji: ":dog:"}')" > /dev/null

  echo "Reminded $ASSIGNEE"
  REMINDED=$((REMINDED + 1))
done

echo "Reminders sent: $REMINDED"
```

### Step 3.6: Wall of Shame — Post Non-Responders to Standup Channel (3:30pm BST / 14:30 UTC)

Run right after Step 3.5. Posts a Snoop-style callout in the standup channel tagging everyone who hasn't replied. Peer visibility drives accountability.

```bash
source ~/.claude/skills/_pm-shared/context.sh

TODAY=$(date -u +%Y-%m-%d)
PING_LOG="/tmp/sync-pings-sent-${TODAY}.json"

if [ ! -f "$PING_LOG" ] || [ "$(jq length "$PING_LOG")" -eq 0 ]; then
  echo "No pings sent today — no wall of shame needed"
  exit 0
fi

# Build list of non-responders
NON_RESPONDERS=""
NON_RESPONDER_COUNT=0

jq -c '.[]' "$PING_LOG" | while read -r ping; do
  CHANNEL=$(echo "$ping" | jq -r '.channel')
  MSG_TS=$(echo "$ping" | jq -r '.msg_ts')
  ASSIGNEE=$(echo "$ping" | jq -r '.assignee')
  SLACK_USER_ID=$(echo "$ping" | jq -r '.slack_user_id')

  REPLY_COUNT=$(curl -s "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$MSG_TS" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq '[.messages[1:][]] | length')

  if [ "$REPLY_COUNT" -eq 0 ]; then
    echo "$ASSIGNEE|$SLACK_USER_ID" >> /tmp/sync-non-responders.txt
  fi
done

NON_RESPONDER_COUNT=$(wc -l < /tmp/sync-non-responders.txt 2>/dev/null | tr -d ' ')
TOTAL_PINGED=$(jq length "$PING_LOG")

if [ "${NON_RESPONDER_COUNT:-0}" -eq 0 ]; then
  echo "Everyone replied — no wall of shame needed. Smooth like a G 🎵"
  exit 0
fi

# Build Slack mentions for non-responders
MENTION_LIST=$(awk -F'|' '{printf "• <@%s>\n", $2}' /tmp/sync-non-responders.txt)
RESPONDED=$((TOTAL_PINGED - NON_RESPONDER_COUNT))

SHAME_MSG="🐕 *Yo fam, Snoop's got a lil situation here* 💨\n\n${RESPONDED}/${TOTAL_PINGED} homies already dropped their updates — big ups to them 🔥\n\nBut these playas still ain't checked in yet:\n\n${MENTION_LIST}\n\n⏰ *Standup digest drops in 30 min, cuz!* Hit up my DM with yo task updates real quick so we ain't goin into scrum blind, ya dig? 🎵\n\n— Snoop D-O-double-G, ya PM bot 🐕"

curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg ch "$SLACK_STANDUP" --arg txt "$SHAME_MSG" '{channel: $ch, text: $txt, username: "Snoop Dogg 🐕", icon_emoji: ":dog:"}')"

echo "Wall of shame posted: $NON_RESPONDER_COUNT non-responders tagged in $SLACK_STANDUP"
rm -f /tmp/sync-non-responders.txt
```

### Step 4: Collect Replies (wait + poll) → /tmp/sync-replies.json

Collect replies from all users pinged today. Run after the final wave/reminder (14:30+ UTC), before daily pulse at 15:00 UTC.

```bash
source ~/.claude/skills/_pm-shared/context.sh

> /tmp/sync-replies.json
echo "[" > /tmp/sync-replies.json

FIRST=true
jq -c '.[]' /tmp/sync-pings-sent.json | while read -r ping; do
  CHANNEL=$(echo "$ping" | jq -r '.channel')
  MSG_TS=$(echo "$ping" | jq -r '.msg_ts')
  ASSIGNEE=$(echo "$ping" | jq -r '.assignee')

  # Fetch thread replies
  REPLIES=$(curl -s "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$MSG_TS" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN")

  # Get replies (skip our ping message)
  USER_REPLIES=$(echo "$REPLIES" | jq '[.messages[1:][]] | map({text, ts, user})')
  REPLY_COUNT=$(echo "$USER_REPLIES" | jq 'length')

  if [ "$REPLY_COUNT" -gt 0 ]; then
    echo "$ASSIGNEE replied ($REPLY_COUNT messages)"
    $FIRST || echo "," >> /tmp/sync-replies.json
    echo "{\"assignee\": \"$ASSIGNEE\", \"replies\": $USER_REPLIES}" >> /tmp/sync-replies.json
    FIRST=false
  else
    echo "$ASSIGNEE ain't replied yet, cuz"
  fi
done

echo "]" >> /tmp/sync-replies.json
echo "Users who replied: $(jq '[.[] | select(.replies | length > 0)] | length' /tmp/sync-replies.json)"
cat /tmp/sync-replies.json
```

### Step 5: Parse Replies + Match to Tasks → /tmp/sync-actions.json

Read the reply text from /tmp/sync-replies.json. For each user's replies, use Claude to parse natural-language updates and match them to existing tasks or flag as new work.

Produce `/tmp/sync-actions.json` with this structure:

```json
[
  {
    "type": "status_update",
    "task_id": "abc123",
    "task_name": "Auth flow",
    "old_status": "to do",
    "new_status": "in progress",
    "comment": "Working on auth flow, expect done by Thursday",
    "assignee": "john"
  },
  {
    "type": "new_task",
    "task_name": "Caching layer for API responses",
    "description": "Started working on a Redis caching layer for API responses to reduce latency",
    "assignee": "john",
    "status": "in progress",
    "needs_github_issue": true,
    "github_repo": "backend-api"
  }
]
```

**Matching rules:**

* Fuzzy-match reply text against task names in /tmp/sync-tasks.json
* Status keywords: "done"/"finished"/"merged" → complete, "working on"/"started"/"in progress" → in progress, "blocked"/"stuck"/"waiting" → blocked, "reviewing"/"in review"/"PR open" → review
* If reply mentions work NOT in any existing task → type: "new_task"
* If reply mentions a PR number → extract and attach to the action
* For new tasks, infer `github_repo` from the REPO_DOMAIN mapping in [context.sh](http://context.sh) if possible

**Write the actions JSON to /tmp/sync-actions.json and output a summary.**

### Step 6: Apply Status Updates to ClickUp (HITL-gated)

**⚠️ HITL CHECKPOINT — Present the parsed actions to the operator for approval before applying.**

Show a Snoop-style summary like:

```
🐕 Yo here's what we about to do, big homie:

Status Updates (3):
 🔥 "Auth flow" (john): to do → in progress — "Workin on auth flow"
 ✅ "Fix login bug" (jane): in progress → complete — "Merged PR #42, that's fire cuz!"
 🚫 "DB migration" (john): in progress → blocked — "Waiting on DBA approval"

New Joints (1):
 🆕 "Caching layer" (john) — in progress — needs GitHub issue in backend-api

Approve these moves? 🎵
```

After HITL approval, apply each update:

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sync-sprint.json)

# Process status updates
jq -c '.[] | select(.type == "status_update")' /tmp/sync-actions.json | while read -r action; do
  TASK_ID=$(echo "$action" | jq -r '.task_id')
  NEW_STATUS=$(echo "$action" | jq -r '.new_status')
  COMMENT=$(echo "$action" | jq -r '.comment')
  TASK_NAME=$(echo "$action" | jq -r '.task_name')

  # Update task status on ClickUp
  cu_api PUT "task/$TASK_ID" "{\"status\": \"$NEW_STATUS\"}"
  echo "Updated $TASK_NAME → $NEW_STATUS"

  # Add comment with context
  if [ -n "$COMMENT" ] && [ "$COMMENT" != "null" ]; then
    cu_api POST "task/$TASK_ID/comment" "{\"comment_text\": \"[🐕 Snoop Sync] $COMMENT\"}"
    echo "  Added comment to $TASK_NAME"
  fi
done
```

### Step 7: Create New Tasks + GitHub Issues (HITL-gated)

**⚠️ HITL CHECKPOINT — Each new task creation requires approval.**

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sync-sprint.json)

jq -c '.[] | select(.type == "new_task")' /tmp/sync-actions.json | while read -r action; do
  TASK_NAME=$(echo "$action" | jq -r '.task_name')
  DESCRIPTION=$(echo "$action" | jq -r '.description')
  ASSIGNEE=$(echo "$action" | jq -r '.assignee')
  STATUS=$(echo "$action" | jq -r '.status')
  NEEDS_ISSUE=$(echo "$action" | jq -r '.needs_github_issue')
  REPO=$(echo "$action" | jq -r '.github_repo // empty')

  # Create GitHub issue first if needed
  ISSUE_URL=""
  if [ "$NEEDS_ISSUE" = "true" ] && [ -n "$REPO" ]; then
    ISSUE_RESPONSE=$(gh issue create \
      --repo "$GITHUB_ORG/$REPO" \
      --title "$TASK_NAME" \
      --body "## Context\n\n$DESCRIPTION\n\n---\n*Created by Snoop Dogg PM Bot 🐕 from Slack status update by @$ASSIGNEE*" \
      2>&1)
    ISSUE_URL=$(echo "$ISSUE_RESPONSE" | grep -oP 'https://github.com/\S+' | head -1)
    echo "Created GitHub issue: $ISSUE_URL"
  fi

  # Look up assignee ClickUp user ID from auto-built mapping
  CU_ASSIGNEE_ID=$(jq -r --arg user "$ASSIGNEE" '.[$user] // empty' /tmp/clickup-user-map.json)

  # Build ClickUp task payload
  PAYLOAD=$(jq -n \
    --arg name "$TASK_NAME" \
    --arg desc "$DESCRIPTION${ISSUE_URL:+\n\nGitHub Issue: $ISSUE_URL}" \
    --arg status "$STATUS" \
    --arg assignee "$CU_ASSIGNEE_ID" \
    '{
      name: $name,
      description: $desc,
      status: $status,
      assignees: (if $assignee != "" then [$assignee | tonumber] else [] end)
    }')

  # Create task in the active sprint list
  cu_api POST "list/$SPRINT_ID/task" "$PAYLOAD"
  echo "Created ClickUp task: $TASK_NAME (assigned to $ASSIGNEE, status: $STATUS)"
done
```

### Step 8: Post Sync Summary to Slack (Snoop Style)

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sync-sprint.json)

UPDATES=$(jq '[.[] | select(.type == "status_update")] | length' /tmp/sync-actions.json)
NEW_TASKS=$(jq '[.[] | select(.type == "new_task")] | length' /tmp/sync-actions.json)
PINGED=$(jq length /tmp/sync-pings-sent.json)
REPLIED=$(jq '[.[] | select(.replies | length > 0)] | length' /tmp/sync-replies.json)

# Build Snoop-style summary
cat > /tmp/sync-summary.md << SEOF
## 🐕 Snoop's Status Sync Complete — $SPRINT_NAME 🎵

Yo what's good fam, here's the daily sync report, ya dig:

- 📤 Homies pinged: $PINGED
- 💬 Homies who replied: $REPLIED
- 🔥 Status updates dropped: $UPDATES
- 🆕 New joints created: $NEW_TASKS

$(jq -r '.[] | select(.type == "status_update") | "• \(.task_name): \(.old_status) → \(.new_status) (\(.assignee))"' /tmp/sync-actions.json | head -10)

$(if [ "$NEW_TASKS" -gt 0 ]; then
  echo "### New Joints 🆕"
  jq -r '.[] | select(.type == "new_task") | "• \(.task_name) (\(.assignee)) — \(.status)"' /tmp/sync-actions.json
fi)

_Keep it real and update yo tasks, cuz! — Snoop D-O-double-G 🐕💨_
SEOF

BODY=$(cat /tmp/sync-summary.md)
slack_post "$SLACK_STANDUP" "🐕 Snoop's Sync — $SPRINT_NAME" "$BODY" "pm-status-sync"
```

### Step 9: Send Snoop Thank-You DMs to People Who Replied

After syncing, send a quick thank-you DM to everyone who responded.

```bash
source ~/.claude/skills/_pm-shared/context.sh

jq -c '.[] | select(.replies | length > 0)' /tmp/sync-replies.json | while read -r reply_block; do
  ASSIGNEE=$(echo "$reply_block" | jq -r '.assignee')
  SLACK_USER_ID=$(jq -r --arg user "$ASSIGNEE" '.[$user] // empty' /tmp/slack-user-map.json)

  if [ -n "$SLACK_USER_ID" ]; then
    USER_NAME=$(jq -r --arg user "$ASSIGNEE" '.[] | select(.username == $user) | .name' /tmp/user-map.json | head -1)
    FIRST_NAME=$(echo "$USER_NAME" | awk '{print $1}')

    THANK_MSG="🐕 Ayy $FIRST_NAME, good lookin out cuz! I synced all yo updates to ClickUp — you ain't gotta touch it. That's how we roll, smooth like a G 🎵💨\n\n— Snoop D-O-double-G 🐕"

    curl -s -X POST "https://slack.com/api/chat.postMessage" \
      -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg ch "$SLACK_USER_ID" --arg txt "$THANK_MSG" '{channel: $ch, text: $txt, username: "Snoop Dogg 🐕", icon_emoji: ":dog:"}')" > /dev/null

    echo "Thanked $ASSIGNEE"
  fi
done
```

