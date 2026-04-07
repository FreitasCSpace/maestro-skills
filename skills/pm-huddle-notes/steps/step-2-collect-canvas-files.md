# Step 2: Collect Canvas Files → /tmp/huddle-files.tsv

Scan each source channel's file list for canvas/quip files within the lookback window.
Uses `files.list` (still works for canvas files attached to messages) with proper timestamp params.
Falls back to scanning `conversations.history` for huddle-generated canvas links if `files.list` returns 0.

```bash
source ~/.claude/skills/_pm-shared/context.sh
OLDEST=$(( $(date +%s) - HUDDLE_LOOKBACK_DAYS * 86400 ))
> /tmp/huddle-files.tsv   # channel<TAB>file_id<TAB>created_ts<TAB>name<TAB>url_private

for ch in $HUDDLE_SOURCE_CHANNELS; do
  CH_ID=$(awk -F'\t' -v n="$ch" '$1==n{print $2}' /tmp/huddle-channels.tsv)
  [ -z "$CH_ID" ] && echo "SKIP: #$ch (no ID)" && continue

  # Primary: files.list for canvas/quip types
  curl -s "https://slack.com/api/files.list?channel=${CH_ID}&ts_from=${OLDEST}&types=spaces.canvas,canvas,quip&count=50" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq -r --arg ch "$ch" \
        '.files[]? | [$ch, .id, (.created|tostring), (.name // "huddle-note"), (.url_private // "")] | @tsv' \
    >> /tmp/huddle-files.tsv

  # Fallback: scan message history for canvas attachments (huddle auto-generated notes)
  curl -s "https://slack.com/api/conversations.history?channel=${CH_ID}&oldest=${OLDEST}&limit=100" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq -r --arg ch "$ch" '
        .messages[]?
        | select(.files? or .attachments?)
        | (.files // [])[]
        | select(.filetype == "canvas" or .filetype == "spaces_canvas" or .filetype == "quip")
        | [$ch, .id, (.created|tostring), (.name // "huddle-note"), (.url_private // "")]
        | @tsv
      ' >> /tmp/huddle-files.tsv 2>/dev/null

  sleep 0.3
done

# Deduplicate by file_id (same file may appear in both queries)
sort -t$'\t' -k2,2 -u /tmp/huddle-files.tsv > /tmp/huddle-files-dedup.tsv
mv /tmp/huddle-files-dedup.tsv /tmp/huddle-files.tsv

echo "Canvas files found: $(wc -l < /tmp/huddle-files.tsv)"
awk -F'\t' '{print $1, $4}' /tmp/huddle-files.tsv
```
