---
name: pm-huddle-notes
description: Fetch Slack huddle notes from #carespace-team (7-day lookback), extract canvas content, write raw notes to GitHub vault repo. Idempotent — skips already-archived notes.
---

# PM Huddle Notes

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- Read-only on Slack — never posts, edits, or deletes messages
- Idempotent — checks vault before writing, skips existing files
- Max 20 files per run
- Skip files with <50 chars of content
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Org: $GITHUB_ORG | Compliance repo: $COMPLIANCE_REPO"
```

## CONFIG
```
SLACK_CHANNEL    = #carespace-team
LOOKBACK_DAYS    = 7
VAULT_REPO       = carespace-ai/carespace-pm-vault
VAULT_PATH       = huddles/
```

---

## EXECUTION

### Step 1: Get Channel ID + Fetch Files → /tmp/huddle-files.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
CHANNEL_ID=$(curl -s "https://slack.com/api/conversations.list?types=public_channel&limit=200" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  | jq -r '.channels[] | select(.name == "carespace-team") | .id')

echo "Channel ID: $CHANNEL_ID"
OLDEST=$(date -d '7 days ago' +%s 2>/dev/null || date -v-7d +%s 2>/dev/null || echo $(($(date +%s) - 604800)))

curl -s "https://slack.com/api/files.list?channel=$CHANNEL_ID&ts_from=$OLDEST&types=quip,canvas" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  | jq '[.files[] | {id, name, created, url_private}]' > /tmp/huddle-files.json

echo "Huddle files found: $(jq length /tmp/huddle-files.json)"
jq -r '.[].name' /tmp/huddle-files.json
```

### Step 2: Check Vault for Existing Files → /tmp/vault-existing.txt

```bash
gh auth status 2>&1 | head -1
gh api repos/carespace-ai/carespace-pm-vault/contents/huddles \
  --jq '.[].name' 2>/dev/null > /tmp/vault-existing.txt || true

echo "Existing vault files: $(wc -l < /tmp/vault-existing.txt)"
```

### Step 3: Download + Write New Huddles → /tmp/huddle-log.txt

```bash
> /tmp/huddle-log.txt
COUNT=0; SKIPPED=0; WRITTEN=0; MAX=20

for row in $(jq -r '.[] | @base64' /tmp/huddle-files.json); do
  [ $COUNT -ge $MAX ] && break
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  CREATED=$(echo "$row"|base64 -d|jq -r '.created')
  URL=$(echo "$row"|base64 -d|jq -r '.url_private')
  FNAME=$(date -d @$CREATED +%Y-%m-%d-%H%M 2>/dev/null || date -r $CREATED +%Y-%m-%d-%H%M 2>/dev/null).md
  FDATE=$(date -d @$CREATED +%Y-%m-%d 2>/dev/null || date -r $CREATED +%Y-%m-%d 2>/dev/null)

  # Skip if already in vault
  if grep -qF "$FNAME" /tmp/vault-existing.txt 2>/dev/null; then
    SKIPPED=$((SKIPPED+1))
    echo "SKIP: $FNAME (exists)" >> /tmp/huddle-log.txt
    continue
  fi

  # Download content
  CONTENT=$(curl -s "$URL" -H "Authorization: Bearer $SLACK_BOT_TOKEN")
  CLEN=${#CONTENT}
  if [ "$CLEN" -lt 50 ]; then
    SKIPPED=$((SKIPPED+1))
    echo "SKIP: $FNAME (empty: ${CLEN} chars)" >> /tmp/huddle-log.txt
    continue
  fi

  # Write to vault
  cat > /tmp/huddle-upload.md << HEOF
---
date: $FDATE
source: slack-huddle
channel: carespace-team
archived_by: pm-huddle-notes
---

$CONTENT
HEOF

  RESULT=$(gh api repos/carespace-ai/carespace-pm-vault/contents/huddles/$FNAME \
    -X PUT \
    -f message="huddle: $FDATE — archived by pm-huddle-notes" \
    -f content="$(base64 -w0 /tmp/huddle-upload.md)" 2>&1 | jq -r '.content.name // "ERROR"')

  echo "WRITE: $FNAME → $RESULT" >> /tmp/huddle-log.txt
  WRITTEN=$((WRITTEN+1))
  COUNT=$((COUNT+1))
  sleep 0.3
done

echo "=== Summary ===" >> /tmp/huddle-log.txt
echo "Scanned: $(jq length /tmp/huddle-files.json) | Written: $WRITTEN | Skipped: $SKIPPED" >> /tmp/huddle-log.txt
cat /tmp/huddle-log.txt
```

Output the summary from `/tmp/huddle-log.txt`. No Slack post needed for this skill.
