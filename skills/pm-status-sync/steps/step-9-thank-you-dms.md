# Step 9: Thank-You DMs to Responders

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
