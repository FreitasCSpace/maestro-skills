# Step 4: Download + Archive New Huddles → /tmp/huddle-log.txt

Downloads canvas content via `url_private`, strips to plaintext, writes to vault.
Uses sha-based GitHub PUT — safe if file already exists (updates instead of erroring).
Filename collision on same-minute huddles resolved with file_id suffix.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/huddle-log.txt
WRITTEN=0; SKIPPED=0; ERRORS=0; ITER=0; MAX=$HUDDLE_MAX_PER_RUN

while IFS=$'\t' read -r channel file_id created_ts name url_private; do
  [ $WRITTEN -ge $MAX ] && echo "HIT MAX $MAX writes — stopping" >> /tmp/huddle-log.txt && break
  ITER=$((ITER+1))

  FDATE=$(date -d "@$created_ts" +%Y-%m-%d 2>/dev/null || echo "unknown")
  FTIME=$(date -d "@$created_ts" +%H%M       2>/dev/null || echo "0000")
  # Include file_id suffix to prevent same-minute collisions
  FNAME="${FDATE}-${FTIME}-${file_id}.md"

  # Skip if already in vault
  if grep -qF "$FNAME" /tmp/vault-existing.txt 2>/dev/null; then
    SKIPPED=$((SKIPPED+1))
    echo "SKIP (exists): $FNAME" >> /tmp/huddle-log.txt
    continue
  fi

  # Skip if no URL
  if [ -z "$url_private" ]; then
    SKIPPED=$((SKIPPED+1))
    echo "SKIP (no url): $name" >> /tmp/huddle-log.txt
    continue
  fi

  # Download raw canvas content
  RAW=$(curl -sL "$url_private" -H "Authorization: Bearer $SLACK_BOT_TOKEN")

  # Strip HTML tags to plaintext if content looks like HTML
  if echo "$RAW" | grep -q '<html\|<!DOCTYPE'; then
    CONTENT=$(echo "$RAW" | sed 's/<[^>]*>//g; /^[[:space:]]*$/d' | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&nbsp;/ /g')
  elif echo "$RAW" | jq . >/dev/null 2>&1; then
    # JSON canvas format — extract text blocks
    CONTENT=$(echo "$RAW" | jq -r '
      .. | objects | select(.type == "text" or .type == "rich_text")
         | (.text // .elements // []) | if type == "array" then .[].text? // "" else . end
    ' 2>/dev/null | grep -v '^$')
  else
    # Already plaintext
    CONTENT="$RAW"
  fi

  CLEN=${#CONTENT}
  if [ "$CLEN" -lt "$HUDDLE_MIN_CONTENT_CHARS" ]; then
    SKIPPED=$((SKIPPED+1))
    echo "SKIP (empty ${CLEN}c): $name" >> /tmp/huddle-log.txt
    continue
  fi

  # Build vault file (use printf to avoid heredoc HEOF collision)
  {
    printf -- '---\n'
    printf 'date: %s\n' "$FDATE"
    printf 'source: slack-huddle\n'
    printf 'channel: "%s"\n' "$channel"
    printf 'slack_file_id: "%s"\n' "$file_id"
    printf 'archived_by: pm-huddle-notes\n'
    printf -- '---\n\n'
    printf '%s\n' "$CONTENT"
  } > /tmp/huddle-upload.md

  B64=$(base64 -w0 /tmp/huddle-upload.md)

  # Check if file exists in vault to get sha (required for update)
  EXISTING_SHA=$(gh api "repos/$HUDDLE_VAULT_REPO/contents/$HUDDLE_VAULT_PATH/$FNAME" \
    --jq '.sha' 2>/dev/null || echo "")

  # Build PUT payload
  if [ -n "$EXISTING_SHA" ]; then
    PAYLOAD=$(jq -n \
      --arg msg "huddle: $FDATE from #$channel — updated by pm-huddle-notes" \
      --arg content "$B64" \
      --arg sha "$EXISTING_SHA" \
      '{message: $msg, content: $content, sha: $sha}')
  else
    PAYLOAD=$(jq -n \
      --arg msg "huddle: $FDATE from #$channel — archived by pm-huddle-notes" \
      --arg content "$B64" \
      '{message: $msg, content: $content}')
  fi

  RESULT=$(gh api "repos/$HUDDLE_VAULT_REPO/contents/$HUDDLE_VAULT_PATH/$FNAME" \
    -X PUT --input - <<< "$PAYLOAD" \
    --jq '.content.name // "ERROR"' 2>&1)

  if [ "$RESULT" = "ERROR" ] || echo "$RESULT" | grep -q '"message"'; then
    ERRORS=$((ERRORS+1))
    echo "ERROR: $FNAME → $RESULT" >> /tmp/huddle-log.txt
  else
    WRITTEN=$((WRITTEN+1))
    echo "WRITE: $FNAME (#$channel, ${CLEN}c)" >> /tmp/huddle-log.txt
  fi

  sleep 0.3
done < /tmp/huddle-files.tsv

echo "=== Summary ===" >> /tmp/huddle-log.txt
echo "Scanned: $ITER | Written: $WRITTEN | Skipped: $SKIPPED | Errors: $ERRORS" >> /tmp/huddle-log.txt
cat /tmp/huddle-log.txt
```
