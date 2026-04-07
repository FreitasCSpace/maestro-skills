# Step 0.5: Build User Mappings → /tmp/clickup-users.json, /tmp/slack-users.json, /tmp/user-map.json

Paginated Slack user fetch. Warns on unmatched users (different email in ClickUp vs Slack).

```bash
source ~/.claude/skills/_pm-shared/context.sh

cu_api GET "team" | jq '[.teams[0].members[] | {
  cu_id: (.user.id | tostring),
  username: .user.username,
  email: (.user.email // "" | ascii_downcase),
  name: ((.user.first_name // "") + " " + (.user.last_name // "") | ltrimstr(" ") | rtrimstr(" "))
}]' > /tmp/clickup-users.json
echo "ClickUp users: $(jq length /tmp/clickup-users.json)"

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

jq -r --slurpfile mapped /tmp/user-map.json '
  .[] | .email as $e |
  if ($mapped[0] | map(.email) | index($e)) == null
  then "WARN: no Slack match for ClickUp user \(.username) (\($e))"
  else empty end
' /tmp/clickup-users.json

jq 'map({(.username): .slack_id}) | add // {}' /tmp/user-map.json > /tmp/slack-user-map.json
jq 'map({(.username): .cu_id})    | add // {}' /tmp/user-map.json > /tmp/clickup-user-map.json

STANDUP_NAME="${SLACK_STANDUP#\#}"
STANDUP_CH_ID=$(jq -r --arg n "$STANDUP_NAME" \
  '.[] | select(.name == $n) | .id' /tmp/slack-members.ndjson 2>/dev/null | head -1)
if [ -z "$STANDUP_CH_ID" ]; then
  STANDUP_CH_ID=$(curl -s "https://slack.com/api/conversations.list?types=public_channel&limit=200" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq -r --arg n "$STANDUP_NAME" '.channels[] | select(.name==$n) | .id')
fi
echo "Standup channel ID: $STANDUP_CH_ID"
echo "$STANDUP_CH_ID" > /tmp/standup-ch-id.txt
```
