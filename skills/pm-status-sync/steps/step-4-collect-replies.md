# Step 4: Collect Replies → /tmp/sync-replies.json

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
