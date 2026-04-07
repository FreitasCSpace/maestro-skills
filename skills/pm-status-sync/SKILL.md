---
name: pm-status-sync
description: Snoop Dogg bot — DMs team for structured task updates, parses replies, syncs to ClickUp, posts wall of shame for non-responders. HITL-gated for writes.
---

# PM Status Sync — "Snoop Dogg" Bot 🐕

Proactive status collection bot with a Snoop Dogg personality. Pings team on Slack in Snoop's style using a **structured reply template** (easy to parse, no AI needed). Syncs updates back to ClickUp. Creates missing tasks and GitHub issues when new work is reported.

**Uses shared context from** `_pm-shared/context.sh`. Requires HITL approval for ClickUp writes and GitHub issue creation.

## BOT PERSONALITY — SNOOP DOGG 🎤

All Slack DM messages written in Snoop Dogg's voice:
- Use "fo shizzle", "ya dig", "what's crackalackin", "drop it like it's hot"
- Call people "cuz", "big homie", "playa"
- Friendly, fun, motivating — but structured reply template is always included verbatim
- Use 🐕 🎵 🔥 💨 emojis liberally
- Sign off: "— Snoop D-O-double-G, ya PM bot 🐕"

## GUARDRAILS
- ⛔ SLACK POST: ONLY to channels in SLACK_ALLOWED_CHANNELS. NEVER to #carespace-team, #general, #eng-general
- DMs to users are allowed (send to user Slack ID as channel)
- ClickUp + GitHub writes are HITL-gated — always show summary and wait for approval
- Never remove or close tasks — only advance status forward
- Respect quiet hours — no pings before 9am or after 6pm user's local time
- Idempotent pings — `/tmp/sync-pings-sent-YYYY-MM-DD.json` tracks daily pings
- **ALL API responses to /tmp files. NEVER dump raw JSON into context.**

## DAILY SCHEDULE (all times UTC)

Scrum at **4:30pm BST (15:30 UTC)**. Daily pulse at **4pm BST (15:00 UTC)**.

| UTC   | BST   | What                          | Who                                    |
|-------|-------|-------------------------------|----------------------------------------|
| 08:00 | 09:00 | **Wave 1** — Steps 0.5–3     | India (1:30pm IST), Portugal (9am WEST)|
| 12:00 | 13:00 | **Wave 2** — Steps 0.5–3     | Brazil (9am BRT), LATAM East           |
| 13:00 | 14:00 | **Wave 3** — Steps 0.5–3     | US East (9am EDT), LATAM West          |
| 14:30 | 15:30 | **Reminder** — Step 3.5      | Non-responders (all TZs)               |
| 14:30 | 15:30 | **Wall of Shame** — Step 3.6 | Non-responders posted to standup       |
| 15:00 | 16:00 | **Collect + Sync** — Steps 4–9 | —                                    |
| 15:30 | 16:30 | Scrum meeting                 | —                                      |

Each wave re-runs Steps 0.5–3. Step 3 is idempotent — skips already-pinged users and defers users outside work hours.

## REPLY FORMAT (enforced template)

Every ping DM includes this verbatim block. Parsing only handles this format:

```
--- your update ---
Task Name: status — optional note
Task Name: status

new: Task Name — brief description of new work

Status options: done | in progress | blocked | review
---
```

---

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | SP field: $SP_FIELD_ID | Standup: $SLACK_STANDUP"
```

## STEP 0.5: Build User Mappings → /tmp/clickup-users.json, /tmp/slack-users.json, /tmp/user-map.json

Paginated Slack user fetch. Warns on unmatched users (different email in ClickUp vs Slack).

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Fetch ClickUp team members
cu_api GET "team" | jq '[.teams[0].members[] | {
  cu_id: (.user.id | tostring),
  username: .user.username,
  email: (.user.email // "" | ascii_downcase),
  name: ((.user.first_name // "") + " " + (.user.last_name // "") | ltrimstr(" ") | rtrimstr(" "))
}]' > /tmp/clickup-users.json
echo "ClickUp users: $(jq length /tmp/clickup-users.json)"

# Fetch Slack members — paginated with cursor
> /tmp/slack-members.ndjson
CURSOR=""
while true; do
  URL="https://slack.com/api/users.list?limit=200"
  [ -n "$CURSOR" ] && URL="${URL}&cursor=${CURSOR}"
  PAGE=$(curl -s "$URL" -H "Authorization: Bearer $SLACK_BOT_TOKEN")
  echo "$PAGE" >> /tmp/slack-members.ndjson; echo >> /tmp/slack-members.ndjson
  CURSOR=$(echo "$PAGE" | jq -r '.response_metadata.next_cursor // empty')
  [ -z "$CURSOR" ] && break
  sleep 0.3
done

jq -s '[.[].members[]? |
  select(.deleted == false and .is_bot == false and .id != "USLACKBOT") |
  {
    slack_id: .id,
    email: (.profile.email // "" | ascii_downcase),
    name: .real_name,
    display_name: .profile.display_name,
    tz: .tz,
    tz_label: .tz_label,
    tz_offset: (.tz_offset // 0)
  }
]' /tmp/slack-members.ndjson > /tmp/slack-users.json
echo "Slack users: $(jq length /tmp/slack-users.json)"

# Cross-reference by email → unified map
jq -n --slurpfile cu /tmp/clickup-users.json --slurpfile sl /tmp/slack-users.json '
  [$cu[0][] | . as $cu_user |
    ($sl[0][] | select(.email != "" and .email == $cu_user.email)) as $sl_user |
    {
      username:     $cu_user.username,
      email:        $cu_user.email,
      name:         $cu_user.name,
      cu_id:        $cu_user.cu_id,
      slack_id:     $sl_user.slack_id,
      tz:           $sl_user.tz,
      tz_label:     $sl_user.tz_label,
      tz_offset:    $sl_user.tz_offset
    }
  ]
' > /tmp/user-map.json

echo "Mapped users: $(jq length /tmp/user-map.json)"

# Warn about ClickUp users with no Slack match
jq -r --slurpfile mapped /tmp/user-map.json '
  .[] | .email as $e |
  if ($mapped[0] | map(.email) | index($e)) == null
  then "WARN: no Slack match for ClickUp user \(.username) (\($e))"
  else empty end
' /tmp/clickup-users.json

# Build lookup maps for downstream steps
jq 'map({(.username): .slack_id}) | add // {}' /tmp/user-map.json > /tmp/slack-user-map.json
jq 'map({(.username): .cu_id})    | add // {}' /tmp/user-map.json > /tmp/clickup-user-map.json

# Pre-resolve standup channel ID (used by wall-of-shame direct postMessage)
STANDUP_NAME="${SLACK_STANDUP#\#}"
STANDUP_CH_ID=$(jq -r --arg n "$STANDUP_NAME" \
  '.[] | select(.name == $n) | .id' /tmp/slack-members.ndjson 2>/dev/null | head -1)
# Fallback: look up via conversations.list
if [ -z "$STANDUP_CH_ID" ]; then
  STANDUP_CH_ID=$(curl -s "https://slack.com/api/conversations.list?types=public_channel&limit=200" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq -r --arg n "$STANDUP_NAME" '.channels[] | select(.name==$n) | .id')
fi
echo "Standup channel ID: $STANDUP_CH_ID"
echo "$STANDUP_CH_ID" > /tmp/standup-ch-id.txt
```

---

## EXECUTION

### Step 1: Find Active Sprint + Load Tasks → /tmp/sync-sprint.json, /tmp/sync-tasks.json

Active sprint = non-done list with `start_date <= now < due_date`.
Paginated task fetch. Uses `date_updated` for staleness.

```bash
source ~/.claude/skills/_pm-shared/context.sh

NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select((.start_date // "0" | tonumber) <= $now)
        | select((.due_date   // "9999999999999" | tonumber) > $now)
      ]
      | sort_by(.start_date // "0" | tonumber)
      | last
      // ([ .lists[] | select(.status.status != "done") ]
          | sort_by(.start_date // "0" | tonumber) | last)
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' > /tmp/sync-sprint.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sync-sprint.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sync-sprint.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO ACTIVE SPRINT — stopping"
  return 0 2>/dev/null; exit 0
fi
echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"

# Paginated task fetch
> /tmp/sync-task-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/sync-page.json
  COUNT=$(jq '.tasks | length' /tmp/sync-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/sync-page.json >> /tmp/sync-task-pages.ndjson
  echo >> /tmp/sync-task-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:80],
      name_lower: (.name | ascii_downcase),
      status: (.status.status | ascii_downcase),
      assignees: [.assignees[].username],
      assignee_ids: [.assignees[].id | tostring],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      updated_ms: (.date_updated // "0" | tonumber),
      url
    }
  ]' /tmp/sync-task-pages.ndjson > /tmp/sync-tasks.json

echo "Sprint tasks: $(jq length /tmp/sync-tasks.json)"
```

### Step 2: Identify Stale/Unupdated Tasks Per User → /tmp/sync-stale-by-user.json

Skip users who already have an in-progress task — they're actively working.
Uses `updated_ms` (from `date_updated`) for staleness, not comment timestamps.

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW_MS=$(( $(date +%s) * 1000 ))
STALE_MS=$(( STALE_TASK_DAYS * 86400 * 1000 ))

# Users with at least one in-progress task → skip them
jq -r '[.[] | select(.status | test("in progress|review|active")) | .assignees[]] | unique | .[]' \
  /tmp/sync-tasks.json > /tmp/sync-active-users.txt
echo "Users with active tasks (will skip): $(wc -l < /tmp/sync-active-users.txt)"

# Group stale tasks by assignee, exclude active users
jq --argjson now "$NOW_MS" --argjson stale "$STALE_MS" \
  --rawfile skip /tmp/sync-active-users.txt '
  def active_users: ($skip | split("\n") | map(select(. != "")));
  [
    .[]
    | select(.status | test("complete|done|closed|resolved") | not)
    | select(($now - .updated_ms) > $stale)
    | select(.assignees | length > 0)
  ]
  | group_by(.assignees[0])
  | map({
      assignee: .[0].assignees[0],
      tasks: [.[] | {
        id, name, status, sp, url,
        days_stale: ((($now - .updated_ms) / 86400000) | floor)
      }]
    })
  | [.[] | select(.assignee as $a | active_users | index($a) | not)]
' /tmp/sync-tasks.json > /tmp/sync-stale-by-user.json

echo "Users with stale tasks: $(jq length /tmp/sync-stale-by-user.json)"
jq -r '.[] | "\(.assignee): \(.tasks | length) stale tasks"' /tmp/sync-stale-by-user.json
```

### Step 3: Ping Users on Slack (Snoop Style + Structured Template)

Timezone-aware, idempotent. Structured reply template included verbatim in every ping.
Run in waves — skips already-pinged users and defers users outside 9am–6pm local time.

```bash
source ~/.claude/skills/_pm-shared/context.sh

NOW_UTC=$(date -u +%s)
TODAY=$(date -u +%Y-%m-%d)
PING_LOG="/tmp/sync-pings-sent-${TODAY}.json"
[ ! -f "$PING_LOG" ] || ! jq empty "$PING_LOG" 2>/dev/null && echo "[]" > "$PING_LOG"

ALREADY_PINGED=$(jq -r '.[].assignee' "$PING_LOG" 2>/dev/null || echo "")
echo "Already pinged today: $(echo "$ALREADY_PINGED" | grep -c . 2>/dev/null || echo 0)"

# Deadline for replies: 15:00 UTC (4pm BST)
DEADLINE_UTC_S=54000   # 15*3600

while IFS= read -r user_block; do
  ASSIGNEE=$(echo "$user_block" | jq -r '.assignee')

  echo "$ALREADY_PINGED" | grep -qx "$ASSIGNEE" && \
    echo "SKIP: $ASSIGNEE already pinged today" && continue

  SLACK_ID=$(jq -r --arg u "$ASSIGNEE" '.[$u] // empty' /tmp/slack-user-map.json)
  [ -z "$SLACK_ID" ] && echo "WARN: no Slack ID for $ASSIGNEE — skipping" && continue

  TZ_OFFSET=$(jq -r --arg u "$ASSIGNEE" \
    '.[] | select(.username==$u) | .tz_offset // 0' /tmp/user-map.json | head -1)
  TZ_LABEL=$(jq -r --arg u "$ASSIGNEE" \
    '.[] | select(.username==$u) | .tz_label // "UTC"' /tmp/user-map.json | head -1)
  USER_LOCAL_H=$(( (NOW_UTC + TZ_OFFSET) % 86400 / 3600 ))

  if [ "$USER_LOCAL_H" -lt 9 ] || [ "$USER_LOCAL_H" -ge 18 ]; then
    echo "DEFER: $ASSIGNEE — local ${USER_LOCAL_H}:xx ($TZ_LABEL), outside 9am-6pm"
    continue
  fi

  # Deadline in user's local time
  DEADLINE_LOCAL_H=$(( (DEADLINE_UTC_S + TZ_OFFSET) % 86400 / 3600 ))
  [ "$DEADLINE_LOCAL_H" -ge 12 ] \
    && DEADLINE_DISP="$((DEADLINE_LOCAL_H - 12 == 0 ? 12 : DEADLINE_LOCAL_H - 12)):00pm" \
    || DEADLINE_DISP="${DEADLINE_LOCAL_H}:00am"

  FIRST_NAME=$(jq -r --arg u "$ASSIGNEE" \
    '.[] | select(.username==$u) | .name | split(" ") | first' /tmp/user-map.json | head -1)

  # Build task list
  TASK_LINES=$(echo "$user_block" | jq -r \
    '.tasks[] | "  🎯 \(.name) (status: `\(.status)`, \(.days_stale)d no update)"')

  # Build structured template with their actual task names
  TEMPLATE_LINES=$(echo "$user_block" | jq -r '.tasks[] | "\(.name): status — optional note"')

  MSG="🐕 Yo what's crackalackin ${FIRST_NAME}! It's ya boy Snoop D-O-double-G, checkin in on yo sprint tasks, ya dig? 🎵

These joints been sittin for a minute:
${TASK_LINES}

💬 *Just hit reply with yo update using this format cuz* (one task per line):

\`\`\`
--- your update ---
${TEMPLATE_LINES}

new: Task Name — describe any new work not in sprint yet

Status options: done | in progress | blocked | review
---\`\`\`

⏰ *Need yo reply by ${DEADLINE_DISP} yo time* so I can cook up the pre-standup digest, ya dig? I'll sync everything to ClickUp fo ya 💨

— Snoop D-O-double-G, ya PM bot 🐕"

  RESP=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
          --arg ch "$SLACK_ID" --arg txt "$MSG" \
          '{channel:$ch, text:$txt, username:"Snoop Dogg 🐕", icon_emoji:":dog:"}')")

  MSG_TS=$(echo "$RESP" | jq -r '.ts // empty')
  MSG_CH=$(echo "$RESP" | jq -r '.channel // empty')

  if [ -n "$MSG_TS" ]; then
    echo "Pinged $ASSIGNEE ($TZ_LABEL, local ${USER_LOCAL_H}:xx) — ts: $MSG_TS"
    TASK_COUNT=$(echo "$user_block" | jq '.tasks | length')
    jq --arg a "$ASSIGNEE" --arg sid "$SLACK_ID" --arg ch "$MSG_CH" \
       --arg ts "$MSG_TS" --argjson tc "$TASK_COUNT" --arg tz "$TZ_LABEL" \
      '. += [{assignee:$a, slack_id:$sid, channel:$ch, msg_ts:$ts, task_count:$tc, tz:$tz}]' \
      "$PING_LOG" > "${PING_LOG}.tmp" && mv "${PING_LOG}.tmp" "$PING_LOG"
  else
    echo "ERROR pinging $ASSIGNEE: $(echo "$RESP" | jq -r '.error // "unknown"')"
  fi

done < <(jq -c '.[]' /tmp/sync-stale-by-user.json)   # process substitution — no subshell

cp "$PING_LOG" /tmp/sync-pings-sent.json
echo "Total pinged today: $(jq length "$PING_LOG")"
```

### Step 3.5: Reminder Ping for Non-Responders (run at 14:30 UTC)

```bash
source ~/.claude/skills/_pm-shared/context.sh
TODAY=$(date -u +%Y-%m-%d)
PING_LOG="/tmp/sync-pings-sent-${TODAY}.json"

[ ! -f "$PING_LOG" ] || [ "$(jq length "$PING_LOG")" -eq 0 ] && \
  echo "No pings today — nothing to remind" && return 0 2>/dev/null

REMINDED=0

while IFS= read -r ping; do
  CHANNEL=$(echo "$ping" | jq -r '.channel')
  MSG_TS=$(echo "$ping"  | jq -r '.msg_ts')
  ASSIGNEE=$(echo "$ping"| jq -r '.assignee')
  SLACK_ID=$(echo "$ping" | jq -r '.slack_id')

  REPLY_COUNT=$(curl -s \
    "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$MSG_TS" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq '[.messages[1:][]] | length')

  [ "$REPLY_COUNT" -gt 0 ] && echo "$ASSIGNEE replied — skipping" && continue

  FIRST_NAME=$(jq -r --arg u "$ASSIGNEE" \
    '.[] | select(.username==$u) | .name | split(" ") | first' /tmp/user-map.json | head -1)

  REMIND_MSG="🐕 Yo ${FIRST_NAME}! Quick reminder cuz — standup digest drops in 30 min 💨

Just hit reply on my earlier message using the template I sent. Even a quick line per task works fo shizzle 🎵

— Snoop D-O-double-G 🐕"

  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$SLACK_ID" --arg txt "$REMIND_MSG" --arg ts "$MSG_TS" \
          '{channel:$ch, text:$txt, thread_ts:$ts, username:"Snoop Dogg 🐕", icon_emoji:":dog:"}')" \
    > /dev/null

  echo "Reminded $ASSIGNEE"
  REMINDED=$(( REMINDED + 1 ))
done < <(jq -c '.[]' "$PING_LOG")

echo "Reminders sent: $REMINDED"
```

### Step 3.6: Wall of Shame — Post Non-Responders to Standup (run at 14:30 UTC)

```bash
source ~/.claude/skills/_pm-shared/context.sh
TODAY=$(date -u +%Y-%m-%d)
PING_LOG="/tmp/sync-pings-sent-${TODAY}.json"
STANDUP_CH_ID=$(cat /tmp/standup-ch-id.txt 2>/dev/null)

[ ! -f "$PING_LOG" ] || [ "$(jq length "$PING_LOG")" -eq 0 ] && \
  echo "No pings today — no wall needed" && return 0 2>/dev/null

[ -z "$STANDUP_CH_ID" ] && echo "ERROR: standup channel ID not resolved — run Step 0.5 first" && return 1

> /tmp/sync-non-responders.txt

while IFS= read -r ping; do
  CHANNEL=$(echo "$ping" | jq -r '.channel')
  MSG_TS=$(echo "$ping"  | jq -r '.msg_ts')
  ASSIGNEE=$(echo "$ping"| jq -r '.assignee')
  SLACK_ID=$(echo "$ping" | jq -r '.slack_id')

  REPLY_COUNT=$(curl -s \
    "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$MSG_TS" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq '[.messages[1:][]] | length')

  [ "$REPLY_COUNT" -eq 0 ] && printf '%s\t%s\n' "$ASSIGNEE" "$SLACK_ID" >> /tmp/sync-non-responders.txt
done < <(jq -c '.[]' "$PING_LOG")

NR_COUNT=$(wc -l < /tmp/sync-non-responders.txt 2>/dev/null | tr -d ' ')
TOTAL=$(jq length "$PING_LOG")
RESPONDED=$(( TOTAL - NR_COUNT ))

if [ "${NR_COUNT:-0}" -eq 0 ]; then
  echo "Everyone replied — smooth like a G 🎵"
  return 0 2>/dev/null
fi

MENTIONS=$(awk -F'\t' '{printf "• <@%s>\n", $2}' /tmp/sync-non-responders.txt)

SHAME_MSG="🐕 *Snoop's got a lil situation here* 💨

${RESPONDED}/${TOTAL} homies already dropped their updates — big ups 🔥

Still ain't checked in:
${MENTIONS}

⏰ Standup digest in 30 min — hit up Snoop's DM real quick with yo task updates! 🎵

— Snoop D-O-double-G 🐕"

curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg ch "$STANDUP_CH_ID" --arg txt "$SHAME_MSG" \
        '{channel:$ch, text:$txt, username:"Snoop Dogg 🐕", icon_emoji:":dog:"}')" \
  > /dev/null

echo "Wall of shame posted: $NR_COUNT non-responders tagged"
rm -f /tmp/sync-non-responders.txt
```

### Step 4: Collect Replies → /tmp/sync-replies.json

Uses process substitution (not pipe) to avoid subshell variable scope issues.
Builds valid JSON by accumulating into array with `jq`.

```bash
source ~/.claude/skills/_pm-shared/context.sh

jq -n '[]' > /tmp/sync-replies.json

while IFS= read -r ping; do
  CHANNEL=$(echo "$ping"  | jq -r '.channel')
  MSG_TS=$(echo "$ping"   | jq -r '.msg_ts')
  ASSIGNEE=$(echo "$ping" | jq -r '.assignee')

  THREAD=$(curl -s \
    "https://slack.com/api/conversations.replies?channel=$CHANNEL&ts=$MSG_TS" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN")

  # Skip first message (our ping) — collect only user replies
  USER_REPLIES=$(echo "$THREAD" | jq '[.messages[1:][]? | {text, ts, user}]')
  REPLY_COUNT=$(echo "$USER_REPLIES" | jq 'length')

  if [ "$REPLY_COUNT" -gt 0 ]; then
    echo "$ASSIGNEE replied ($REPLY_COUNT messages)"
    jq --arg a "$ASSIGNEE" --argjson replies "$USER_REPLIES" \
      '. += [{assignee: $a, replies: $replies}]' \
      /tmp/sync-replies.json > /tmp/sync-replies.tmp \
      && mv /tmp/sync-replies.tmp /tmp/sync-replies.json
  else
    echo "$ASSIGNEE ain't replied yet, cuz"
  fi
done < <(jq -c '.[]' /tmp/sync-pings-sent.json)

echo "Users who replied: $(jq length /tmp/sync-replies.json)"
```

### Step 5: Parse Structured Replies → /tmp/sync-actions.json

Parses the structured template format. No AI needed — line-by-line regex matching.

**Status keyword map:**
- `done / finished / merged / closed / completed` → `closed`
- `in progress / working / started / active` → `in progress`
- `blocked / stuck / waiting` → `blocked`
- `review / reviewing / pr open / in review` → `review`

**Task name matching:** case-insensitive substring match against `/tmp/sync-tasks.json`.

```bash
source ~/.claude/skills/_pm-shared/context.sh

jq -n '[]' > /tmp/sync-actions.json

# Load task names for matching (lowercase)
jq -r '.[] | [.id, .name_lower, .status, .url] | @tsv' /tmp/sync-tasks.json \
  > /tmp/sync-task-index.tsv

map_status() {
  local raw=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | xargs)
  case "$raw" in
    *done*|*finished*|*merged*|*closed*|*completed*) echo "closed" ;;
    *in\ progress*|*working*|*started*|*active*)     echo "in progress" ;;
    *blocked*|*stuck*|*waiting*)                     echo "blocked" ;;
    *review*|*reviewing*|*pr\ open*|*in\ review*)    echo "review" ;;
    *) echo "$raw" ;;
  esac
}

find_task_id() {
  local needle=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  # Exact match first, then substring
  awk -F'\t' -v n="$needle" \
    'BEGIN{best="";bestid=""} $2==n{print $1; exit} index($2,n)>0{bestid=$1;best=$2} END{print bestid}' \
    /tmp/sync-task-index.tsv | head -1
}

find_task_status() {
  local id="$1"
  awk -F'\t' -v i="$id" '$1==i{print $3}' /tmp/sync-task-index.tsv | head -1
}

find_task_url() {
  local id="$1"
  awk -F'\t' -v i="$id" '$1==i{print $4}' /tmp/sync-task-index.tsv | head -1
}

while IFS= read -r user_block; do
  ASSIGNEE=$(echo "$user_block" | jq -r '.assignee')

  # Concatenate all reply texts into one string
  ALL_TEXT=$(echo "$user_block" | jq -r '.replies[].text' | tr '\n' '\n')

  # Extract content between --- markers
  BLOCK=$(echo "$ALL_TEXT" | awk '/^---.*your update/{found=1; next} found && /^---/{exit} found{print}')
  [ -z "$BLOCK" ] && BLOCK="$ALL_TEXT"   # fallback: parse entire reply

  while IFS= read -r line; do
    line=$(echo "$line" | xargs)
    [ -z "$line" ] && continue

    # New task: "new: Task Name — description"
    if echo "$line" | grep -qiE '^new:'; then
      TASK_NAME=$(echo "$line" | sed 's/^new://i' | awk -F'—' '{print $1}' | xargs)
      DESCRIPTION=$(echo "$line" | awk -F'—' '{print $2}' | xargs)
      jq --arg a "$ASSIGNEE" --arg n "$TASK_NAME" --arg d "${DESCRIPTION:-$TASK_NAME}" \
        '. += [{type:"new_task", task_name:$n, description:$d, assignee:$a,
                status:"in progress", needs_github_issue:true}]' \
        /tmp/sync-actions.json > /tmp/sync-actions.tmp \
        && mv /tmp/sync-actions.tmp /tmp/sync-actions.json
      echo "NEW: $ASSIGNEE — $TASK_NAME"
      continue
    fi

    # Status update: "Task Name: status — optional note"
    if echo "$line" | grep -qE '^[^:]+:'; then
      TASK_RAW=$(echo "$line" | awk -F':' '{print $1}' | xargs)
      REST=$(echo "$line" | cut -d: -f2- | xargs)
      STATUS_RAW=$(echo "$REST" | awk -F'—' '{print $1}' | xargs)
      NOTE=$(echo "$REST" | awk -F'—' '{print $2}' | xargs)
      NEW_STATUS=$(map_status "$STATUS_RAW")
      TASK_ID=$(find_task_id "$TASK_RAW")

      if [ -n "$TASK_ID" ]; then
        OLD_STATUS=$(find_task_status "$TASK_ID")
        TASK_URL=$(find_task_url "$TASK_ID")
        jq --arg a "$ASSIGNEE" --arg id "$TASK_ID" \
           --arg tn "$TASK_RAW" --arg os "$OLD_STATUS" \
           --arg ns "$NEW_STATUS" --arg note "$NOTE" --arg url "$TASK_URL" \
          '. += [{type:"status_update", task_id:$id, task_name:$tn,
                  old_status:$os, new_status:$ns, comment:$note,
                  assignee:$a, url:$url}]' \
          /tmp/sync-actions.json > /tmp/sync-actions.tmp \
          && mv /tmp/sync-actions.tmp /tmp/sync-actions.json
        echo "UPDATE: $ASSIGNEE — $TASK_RAW → $NEW_STATUS"
      else
        echo "WARN: no task match for '$TASK_RAW' ($ASSIGNEE) — skipping"
      fi
    fi
  done <<< "$BLOCK"

done < <(jq -c '.[]' /tmp/sync-replies.json)

echo "=== Actions parsed ==="
echo "Status updates: $(jq '[.[]|select(.type=="status_update")]|length' /tmp/sync-actions.json)"
echo "New tasks:      $(jq '[.[]|select(.type=="new_task")]|length'      /tmp/sync-actions.json)"
```

### Step 6: Apply Status Updates to ClickUp ⚠️ HITL-gated

**Show this summary and wait for approval before applying:**

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "🐕 Yo here's what we about to do, big homie:"
echo ""
echo "Status Updates:"
jq -r '.[] | select(.type=="status_update") |
  "  \(.old_status) → \(.new_status)  \(.task_name) (\(.assignee))\(if .comment != "" then " — \"\(.comment)\"" else "" end)"
' /tmp/sync-actions.json

echo ""
echo "New Joints:"
jq -r '.[] | select(.type=="new_task") |
  "  🆕 \(.task_name) (\(.assignee)) — \(.description)"
' /tmp/sync-actions.json

echo ""
echo "Approve these moves? (operator confirms before continuing)"
```

After HITL approval, apply updates:

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Status must match ClickUp's configured status names exactly — use lowercase
# Map our canonical values to ClickUp defaults
map_cu_status() {
  case "$1" in
    "closed")      echo "closed" ;;
    "in progress") echo "in progress" ;;
    "blocked")     echo "blocked" ;;
    "review")      echo "review" ;;
    *)             echo "$1" ;;
  esac
}

> /tmp/sync-apply-log.txt

while IFS= read -r action; do
  TASK_ID=$(echo "$action"   | jq -r '.task_id')
  TASK_NAME=$(echo "$action" | jq -r '.task_name')
  NEW_STATUS=$(echo "$action"| jq -r '.new_status')
  COMMENT=$(echo "$action"   | jq -r '.comment // ""')
  ASSIGNEE=$(echo "$action"  | jq -r '.assignee')
  CU_STATUS=$(map_cu_status "$NEW_STATUS")

  RESULT=$(cu_api PUT "task/$TASK_ID" \
    "$(jq -n --arg s "$CU_STATUS" '{status:$s}')")
  if echo "$RESULT" | jq -e '.id' > /dev/null 2>&1; then
    echo "UPDATED: $TASK_NAME → $CU_STATUS" >> /tmp/sync-apply-log.txt
  else
    echo "ERROR: $TASK_NAME — $(echo "$RESULT" | jq -r '.err // "unknown"')" >> /tmp/sync-apply-log.txt
  fi

  if [ -n "$COMMENT" ] && [ "$COMMENT" != "null" ]; then
    cu_api POST "task/$TASK_ID/comment" \
      "$(jq -n --arg c "[🐕 Snoop Sync — $ASSIGNEE] $COMMENT" '{comment_text:$c}')" \
      > /dev/null
  fi
  sleep 0.3
done < <(jq -c '.[] | select(.type=="status_update")' /tmp/sync-actions.json)

cat /tmp/sync-apply-log.txt
```

### Step 7: Create New Tasks + GitHub Issues ⚠️ HITL-gated

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sync-sprint.json)
> /tmp/sync-create-log.txt

while IFS= read -r action; do
  TASK_NAME=$(echo "$action"  | jq -r '.task_name')
  DESCRIPTION=$(echo "$action"| jq -r '.description')
  ASSIGNEE=$(echo "$action"   | jq -r '.assignee')
  STATUS=$(echo "$action"     | jq -r '.status')
  NEEDS_ISSUE=$(echo "$action"| jq -r '.needs_github_issue')

  ISSUE_URL=""
  if [ "$NEEDS_ISSUE" = "true" ]; then
    # Infer repo from assignee's domain or default to carespace-admin
    DOMAIN=$(jq -r --arg u "$ASSIGNEE" \
      'to_entries[] | select(.value==$u) | .key' /tmp/clickup-user-map.json | head -1)
    REPO=$(awk -v d="$DOMAIN" -F'"' '
      /\[.*\]=/ { key=$2 }
      /=/ && key==d { split($0,a,"\""); print a[2]; exit }
    ' /dev/null 2>/dev/null || echo "carespace-admin")

    ISSUE_RESP=$(gh issue create \
      --repo "$GITHUB_ORG/$REPO" \
      --title "$TASK_NAME" \
      --body "$(printf '## Context\n\n%s\n\n---\n*Created by Snoop Dogg PM Bot 🐕 from status update by @%s*' \
                "$DESCRIPTION" "$ASSIGNEE")" 2>&1)
    ISSUE_URL=$(echo "$ISSUE_RESP" | grep -oP 'https://github\.com/\S+' | head -1)
    echo "GH issue: $ISSUE_URL" >> /tmp/sync-create-log.txt
  fi

  CU_ASSIGNEE_ID=$(jq -r --arg u "$ASSIGNEE" '.[$u] // empty' /tmp/clickup-user-map.json)
  DESC="${DESCRIPTION}${ISSUE_URL:+\n\nGitHub: $ISSUE_URL}"

  PAYLOAD=$(jq -n \
    --arg name "$TASK_NAME" \
    --arg desc "$DESC" \
    --arg status "$STATUS" \
    --argjson assignees "$([ -n "$CU_ASSIGNEE_ID" ] && echo "[$CU_ASSIGNEE_ID]" || echo '[]')" \
    '{name:$name, description:$desc, status:$status, assignees:$assignees}')

  RESULT=$(cu_api POST "list/$SPRINT_ID/task" "$PAYLOAD")
  TASK_ID=$(echo "$RESULT" | jq -r '.id // "ERROR"')
  echo "CREATED: $TASK_NAME → $TASK_ID" >> /tmp/sync-create-log.txt
  sleep 0.3
done < <(jq -c '.[] | select(.type=="new_task")' /tmp/sync-actions.json)

cat /tmp/sync-create-log.txt
```

### Step 8: Post Sync Summary to Standup Channel

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sync-sprint.json)

UPDATES=$(jq  '[.[] | select(.type=="status_update")] | length' /tmp/sync-actions.json)
NEW_TASKS=$(jq '[.[] | select(.type=="new_task")]     | length' /tmp/sync-actions.json)
PINGED=$(jq  length /tmp/sync-pings-sent.json)
REPLIED=$(jq length /tmp/sync-replies.json)

UPDATE_LINES=$(jq -r '
  .[] | select(.type=="status_update") |
  "• \(.task_name): \(.old_status) → \(.new_status) (\(.assignee))"
' /tmp/sync-actions.json | head -10)

NEW_LINES=$(jq -r '
  .[] | select(.type=="new_task") |
  "• 🆕 \(.task_name) (\(.assignee))"
' /tmp/sync-actions.json)

{
  printf '🐕 *Snoop Sync Complete — %s* 🎵\n\n' "$SPRINT_NAME"
  printf '📤 Pinged: %s | 💬 Replied: %s | 🔥 Updates: %s | 🆕 New: %s\n\n' \
    "$PINGED" "$REPLIED" "$UPDATES" "$NEW_TASKS"
  [ -n "$UPDATE_LINES" ] && printf '*Status Updates*\n%s\n\n' "$UPDATE_LINES"
  [ -n "$NEW_LINES"    ] && printf '*New Joints*\n%s\n\n' "$NEW_LINES"
  printf '_Keep it real and update yo tasks, cuz! — Snoop D-O-double-G 🐕💨_\n'
} > /tmp/sync-summary.md

BODY=$(cat /tmp/sync-summary.md)
slack_post "$SLACK_STANDUP" "🐕 Snoop Sync — $SPRINT_NAME" "$BODY" "pm-status-sync"
```

### Step 9: Thank-You DMs to Responders

```bash
source ~/.claude/skills/_pm-shared/context.sh

while IFS= read -r reply_block; do
  ASSIGNEE=$(echo "$reply_block" | jq -r '.assignee')
  SLACK_ID=$(jq -r --arg u "$ASSIGNEE" '.[$u] // empty' /tmp/slack-user-map.json)
  [ -z "$SLACK_ID" ] && continue

  FIRST_NAME=$(jq -r --arg u "$ASSIGNEE" \
    '.[] | select(.username==$u) | .name | split(" ") | first' \
    /tmp/user-map.json | head -1)

  THANK_MSG="🐕 Ayy ${FIRST_NAME}, good lookin out cuz! 🔥

I synced all yo updates to ClickUp — you ain't gotta touch it. That's how we roll, smooth like a G 🎵💨

— Snoop D-O-double-G 🐕"

  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$SLACK_ID" --arg txt "$THANK_MSG" \
          '{channel:$ch, text:$txt, username:"Snoop Dogg 🐕", icon_emoji:":dog:"}')" \
    > /dev/null

  echo "Thanked $ASSIGNEE"
done < <(jq -c '.[]' /tmp/sync-replies.json)
```
