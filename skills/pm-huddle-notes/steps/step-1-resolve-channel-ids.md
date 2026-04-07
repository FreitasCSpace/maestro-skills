# Step 1: Resolve Channel IDs → /tmp/huddle-channels.tsv

`files.list` and `conversations.history` require channel IDs, not names.
Paginate `conversations.list` to handle workspaces with >200 channels.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/huddle-channels.tsv   # name<TAB>id

CURSOR=""
while true; do
  URL="https://slack.com/api/conversations.list?types=public_channel,private_channel&limit=200"
  [ -n "$CURSOR" ] && URL="${URL}&cursor=${CURSOR}"

  PAGE=$(curl -s "$URL" -H "Authorization: Bearer $SLACK_BOT_TOKEN")
  echo "$PAGE" | jq -r '.channels[] | [.name, .id] | @tsv' >> /tmp/huddle-channels.tsv

  CURSOR=$(echo "$PAGE" | jq -r '.response_metadata.next_cursor // empty')
  [ -z "$CURSOR" ] && break
  sleep 0.3
done

# Verify all source channels resolved
for ch in $HUDDLE_SOURCE_CHANNELS; do
  ID=$(awk -F'\t' -v n="$ch" '$1==n{print $2}' /tmp/huddle-channels.tsv)
  if [ -z "$ID" ]; then
    echo "WARNING: channel '$ch' not found in workspace — will skip"
  else
    echo "Resolved: #$ch → $ID"
  fi
done
```
