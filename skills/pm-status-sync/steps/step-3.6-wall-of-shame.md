# Step 3.6: Wall of Shame — Post Non-Responders to Standup (run at 14:30 UTC)

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
