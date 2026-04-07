# Step 3.5: Reminder Ping for Non-Responders (run at 14:30 UTC)

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
