---
name: pm-huddle-notes
description: Scan #pm-standup and #carespace-team for huddle note canvases (7-day lookback), extract plaintext content, archive to GitHub vault. Idempotent — skips already-archived files.
---

# PM Huddle Notes

**Fully autonomous. Read-only on Slack. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ Read-only on Slack — NEVER posts, edits, or deletes messages in any channel
- ⛔ Only reads from channels in $HUDDLE_SOURCE_CHANNELS — never substitutes
- Idempotent — checks vault before writing, skips existing files
- Max $HUDDLE_MAX_PER_RUN files written per run
- Skip files with fewer than $HUDDLE_MIN_CONTENT_CHARS chars of content
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**
- GitHub vault writes use sha-based update (safe re-run — never duplicates)

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sources: $HUDDLE_SOURCE_CHANNELS | Vault: $HUDDLE_VAULT_REPO/$HUDDLE_VAULT_PATH"
```

---

## EXECUTION

### Step 1: Resolve Channel IDs → /tmp/huddle-channels.tsv

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

### Step 2: Collect Canvas Files → /tmp/huddle-files.tsv

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

### Step 3: Load Vault Index → /tmp/vault-existing.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Paginate vault contents (handles >1000 files)
> /tmp/vault-existing.txt
PAGE=1
while true; do
  RESULT=$(gh api "repos/$HUDDLE_VAULT_REPO/contents/$HUDDLE_VAULT_PATH?per_page=100&page=$PAGE" \
    --jq '.[].name' 2>/dev/null)
  [ -z "$RESULT" ] && break
  echo "$RESULT" >> /tmp/vault-existing.txt
  COUNT=$(echo "$RESULT" | wc -l)
  [ "$COUNT" -lt 100 ] && break
  PAGE=$((PAGE+1))
done

echo "Existing vault files: $(wc -l < /tmp/vault-existing.txt)"
```

### Step 4: Download + Archive New Huddles → /tmp/huddle-log.txt

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
