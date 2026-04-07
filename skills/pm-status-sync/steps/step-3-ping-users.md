# Step 3: Ping Users on Slack (Snoop Style + Structured Template)

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

  DEADLINE_LOCAL_H=$(( (DEADLINE_UTC_S + TZ_OFFSET) % 86400 / 3600 ))
  [ "$DEADLINE_LOCAL_H" -ge 12 ] \
    && DEADLINE_DISP="$((DEADLINE_LOCAL_H - 12 == 0 ? 12 : DEADLINE_LOCAL_H - 12)):00pm" \
    || DEADLINE_DISP="${DEADLINE_LOCAL_H}:00am"

  FIRST_NAME=$(jq -r --arg u "$ASSIGNEE" \
    '.[] | select(.username==$u) | .name | split(" ") | first' /tmp/user-map.json | head -1)

  TASK_LINES=$(echo "$user_block" | jq -r \
    '.tasks[] | "  🎯 \(.name) (status: `\(.status)`, \(.days_stale)d no update)"')

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

done < <(jq -c '.[]' /tmp/sync-stale-by-user.json)

cp "$PING_LOG" /tmp/sync-pings-sent.json
echo "Total pinged today: $(jq length "$PING_LOG")"
```
