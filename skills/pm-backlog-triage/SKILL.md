---
name: pm-backlog-triage
description: Import GitHub issues into ClickUp backlog, deduplicate, normalize priorities, estimate story points, triage, and post health report to Slack. Idempotent — safe to run repeatedly.
---

# PM Backlog Triage

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- Delete ClickUp tasks whose linked GitHub issue no longer exists (404/closed) — no cap
- Max per run: 50 creates, 50 SP updates
- Only set SP on tasks with zero SP — never overwrite
- Never set priority to urgent unless tagged security/compliance
- Idempotency: `pm-bot-imported` tag prevents re-import of same issues
- **ALL API responses go to /tmp files. NEVER dump raw JSON into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Org: $GITHUB_ORG | Backlog: $LIST_MASTER_BACKLOG | SP field: $SP_FIELD_ID"
```

---

## EXECUTION

### Step 1: Collect GitHub Issues → /tmp/gh-issues.tsv

```bash
source ~/.claude/skills/_pm-shared/context.sh
gh auth status 2>&1 | head -1

> /tmp/gh-issues.tsv
for repo in $(gh repo list $GITHUB_ORG --limit 100 --json name --no-archived --jq '.[].name' 2>/dev/null); do
  DOMAIN=$(get_domain "$repo")
  gh issue list --repo $GITHUB_ORG/$repo --state open --json number,title,url,labels --limit 50 2>/dev/null \
    | jq -r --arg r "$repo" --arg d "$DOMAIN" '.[] | [$r, (.number|tostring), .title[0:80], .url, ((.labels[0].name) // "none"), $d] | @tsv' \
    >> /tmp/gh-issues.tsv 2>/dev/null
done

echo "=== GitHub Issues: $(wc -l < /tmp/gh-issues.tsv) total ==="
cut -f1 /tmp/gh-issues.tsv | sort | uniq -c | sort -rn | head -10
```

### Step 2: Load ClickUp Backlog → /tmp/cu-backlog.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/cu-backlog-raw.json
PAGE=0
while true; do
  cu_api GET "list/$LIST_MASTER_BACKLOG/task?include_closed=false&subtasks=true&page=$PAGE" > /tmp/cu-page.json
  COUNT=$(jq '.tasks | length' /tmp/cu-page.json)
  [ "$COUNT" = "0" ] && break
  jq --arg cf "$SP_FIELD_ID" '.tasks[] | {id, name: .name[0:80], desc: (.description // "")[0:120], tags: [.tags[].name], pri: (.priority.priority // "4"), sp: ((.custom_fields[] | select(.id==$cf) | .value) // 0)}' /tmp/cu-page.json >> /tmp/cu-backlog-raw.json
  PAGE=$((PAGE + 1))
  sleep 0.3
done

# Build URL index for dedup
grep -oP 'https://github\.com/[^\s"]+' /tmp/cu-backlog-raw.json 2>/dev/null | sort -u > /tmp/cu-urls.txt
# Check for pm-bot-imported tags
jq -r 'select(.tags | any(. == "pm-bot-imported")) | .name' /tmp/cu-backlog-raw.json 2>/dev/null | sort -u > /tmp/cu-imported.txt

echo "ClickUp backlog entries: $(wc -l < /tmp/cu-backlog-raw.json)"
echo "Known GitHub URLs: $(wc -l < /tmp/cu-urls.txt)"
echo "Already imported: $(wc -l < /tmp/cu-imported.txt)"
```

### Step 3: Validate GitHub Issues in ClickUp → /tmp/stale-issues-log.txt

Check each ClickUp backlog task that has a GitHub URL in its description. If the GitHub issue no longer exists (404) or is closed, delete the ClickUp task.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/stale-issues-log.txt
DELETED=0; VALID=0

# Re-fetch backlog with descriptions to extract GitHub URLs
cu_api GET "list/$LIST_MASTER_BACKLOG/task?include_closed=false&subtasks=true&page=0" \
  | jq '[.tasks[] | {id, name: .name[0:80], desc: (.description // "")}]' \
  > /tmp/cu-backlog-check.json

TOTAL_CHECK=$(jq length /tmp/cu-backlog-check.json)
echo "Checking $TOTAL_CHECK backlog tasks for stale GitHub issues..."

for row in $(jq -r '.[] | @base64' /tmp/cu-backlog-check.json); do
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  DESC=$(echo "$row"|base64 -d|jq -r '.desc')

  # Extract GitHub issue URL from description
  GH_URL=$(echo "$DESC" | grep -oP 'https://github\.com/[^/]+/[^/]+/issues/\d+' | head -1)
  [ -z "$GH_URL" ] && continue

  # Extract owner/repo#number from URL
  GH_REPO=$(echo "$GH_URL" | grep -oP 'github\.com/\K[^/]+/[^/]+')
  GH_NUM=$(echo "$GH_URL" | grep -oP 'issues/\K\d+')

  # Check if issue still exists and is open
  ISSUE_STATE=$(gh issue view "$GH_NUM" --repo "$GH_REPO" --json state --jq '.state' 2>/dev/null)

  if [ -z "$ISSUE_STATE" ]; then
    # 404 — issue doesn't exist
    cu_api DELETE "task/$ID" > /dev/null
    echo "DELETED (404): $NAME → $GH_URL" >> /tmp/stale-issues-log.txt
    DELETED=$((DELETED+1))
  elif [ "$ISSUE_STATE" = "CLOSED" ]; then
    # Issue was closed on GitHub
    cu_api DELETE "task/$ID" > /dev/null
    echo "DELETED (closed): $NAME → $GH_URL" >> /tmp/stale-issues-log.txt
    DELETED=$((DELETED+1))
  else
    VALID=$((VALID+1))
  fi

  sleep 0.3
done

echo "=== Stale Issue Cleanup ===" >> /tmp/stale-issues-log.txt
echo "Checked: $TOTAL_CHECK | Valid: $VALID | Deleted: $DELETED" >> /tmp/stale-issues-log.txt
cat /tmp/stale-issues-log.txt
```

### Step 4: Import New Issues → /tmp/import-log.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/new-issues.tsv
> /tmp/import-log.txt
IMPORTED=0; SKIPPED=0; MAX=50

while IFS=$'\t' read -r repo num title url label domain; do
  if grep -qF "$url" /tmp/cu-urls.txt 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
  else
    echo -e "$repo\t$num\t$title\t$url\t$label\t$domain" >> /tmp/new-issues.tsv
  fi
done < /tmp/gh-issues.tsv

NEW=$(wc -l < /tmp/new-issues.tsv)
echo "New: $NEW | Skipped (dedup): $SKIPPED" | tee /tmp/import-log.txt

COUNT=0
while IFS=$'\t' read -r repo num title url label domain; do
  [ $COUNT -ge $MAX ] && echo "HIT MAX $MAX — stopping" >> /tmp/import-log.txt && break

  # Priority: security/compliance=1 (urgent), bug=2 (high), enhancement/feature=3, other=4
  case "$label" in
    security|compliance) PRI=1;;
    bug) PRI=2;;
    enhancement|feature) PRI=3;;
    *) PRI=4;;
  esac

  # SP estimation from context.py heuristics
  case "$label" in
    security) SP=8;;
    bug)
      case "$PRI" in 1) SP=8;; 2) SP=5;; *) SP=2;; esac;;
    feature|enhancement)
      echo "$title" | grep -qiE "refactor|rewrite|migrate|redesign" && SP=21 || SP=5;;
    *) SP=2;;
  esac

  # Domain lead for auto-assignment
  LEAD="${DOMAIN_LEAD[$domain]:-}"

  PAYLOAD=$(jq -n \
    --arg n "[$repo] $title" \
    --arg d "GitHub: $url\nDomain: $domain\nLabel: $label" \
    --argjson p $PRI \
    --arg tag1 "pm-bot-imported" \
    --arg tag2 "$domain" \
    '{name:$n, description:$d, priority:$p, tags:[$tag1,$tag2]}')

  RES=$(cu_api POST "list/$LIST_MASTER_BACKLOG/task" "$PAYLOAD" | jq -r '.id // "ERROR"')

  # Set SP via custom field
  if [ "$RES" != "ERROR" ] && [ -n "$RES" ]; then
    cu_api POST "task/$RES/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null

    # Assign domain lead if available
    if [ -n "$LEAD" ]; then
      cu_api POST "task/$RES" "{\"assignees\":{\"add\":[$LEAD]}}" > /dev/null
    fi
  fi

  echo "IMPORT $repo#$num → $RES (pri=$PRI, sp=$SP, domain=$domain)" >> /tmp/import-log.txt
  COUNT=$((COUNT+1)); IMPORTED=$((IMPORTED+1)); sleep 0.3
done < /tmp/new-issues.tsv

echo "Imported: $IMPORTED" >> /tmp/import-log.txt
cat /tmp/import-log.txt
```

### Step 5: Estimate Missing SP → /tmp/sp-log.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/sp-log.txt

# Fetch tasks with no SP
cu_api GET "list/$LIST_MASTER_BACKLOG/task?include_closed=false&subtasks=true&page=0" \
  | jq --arg cf "$SP_FIELD_ID" \
    '[.tasks[] | {id, name: .name[0:60], tags: [.tags[].name], sp: ((.custom_fields[] | select(.id==$cf) | .value) // 0)} | select(.sp == 0 or .sp == null)]' \
  > /tmp/no-sp.json

TOTAL=$(jq length /tmp/no-sp.json)
echo "Tasks missing SP: $TOTAL" | tee /tmp/sp-log.txt
COUNT=0; MAX=50

for row in $(jq -r '.[] | @base64' /tmp/no-sp.json); do
  [ $COUNT -ge $MAX ] && break
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  TAGS=$(echo "$row"|base64 -d|jq -r '.tags|join(",")')

  # SP estimation heuristic from context.py
  SP=2  # default
  case "$TAGS" in
    *security*|*compliance*) SP=8;;
    *bug*)
      echo "$NAME" | grep -qiE "critical|crash|data.loss" && SP=8 || SP=5;;
    *feature*|*enhancement*)
      echo "$NAME" | grep -qiE "refactor|rewrite|migrate|redesign" && SP=21
      echo "$NAME" | grep -qiE "add|create|new|implement" && SP=13
      [ $SP -eq 2 ] && SP=5;;
    *infra*|*ci*|*config*) SP=3;;
  esac

  cu_api POST "task/$ID/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null
  echo "SP: $NAME → ${SP}" >> /tmp/sp-log.txt
  COUNT=$((COUNT+1)); sleep 0.2
done

echo "SP set: $COUNT" >> /tmp/sp-log.txt
tail -5 /tmp/sp-log.txt
```

### Step 6: Triage Report → /tmp/triage-report.md

```bash
source ~/.claude/skills/_pm-shared/context.sh

cu_api GET "list/$LIST_MASTER_BACKLOG/task?include_closed=false&subtasks=true&page=0" \
  | jq '[.tasks[] | {name: .name[0:60], pri: (.priority.priority//"4"), assignees: ([.assignees[].username]|join(",")), age: (((now-(.date_created/1000))/86400)|floor), tags: [.tags[].name]}]' \
  > /tmp/triage.json

TOTAL=$(jq length /tmp/triage.json)
BUGS=$(jq '[.[]|select(.tags|any(.=="bug"))]|length' /tmp/triage.json)
FEATS=$(jq '[.[]|select(.tags|any(.=="enhancement" or .=="feature"))]|length' /tmp/triage.json)
URG=$(jq '[.[]|select(.pri=="1")]|length' /tmp/triage.json)
HIGH=$(jq '[.[]|select(.pri=="2")]|length' /tmp/triage.json)
NORM=$(jq '[.[]|select(.pri=="3")]|length' /tmp/triage.json)
LOW=$(jq '[.[]|select(.pri=="4")]|length' /tmp/triage.json)
UNASSIGNED=$(jq '[.[]|select(.assignees=="" and .age>7)]|length' /tmp/triage.json)
AGING=$(jq "[.[]|select(.age>$AGING_TASK_DAYS)]|length" /tmp/triage.json)
STALE=$(jq "[.[]|select(.age>$STALE_TASK_DAYS and .age<=$AGING_TASK_DAYS)]|length" /tmp/triage.json)

cat > /tmp/triage-report.md << REOF
# Backlog Health — $(date +%Y-%m-%d)

## Summary
- **Total:** $TOTAL tasks | **Bugs:** $BUGS | **Features:** $FEATS
- **Priority:** Urgent=$URG High=$HIGH Normal=$NORM Low=$LOW

## Actions Taken
$(cat /tmp/import-log.txt | tail -3)
$(tail -1 /tmp/sp-log.txt)

## Needs Attention
- Unassigned >7d: $UNASSIGNED
- Stale >${STALE_TASK_DAYS}d: $STALE
- Aging >${AGING_TASK_DAYS}d: $AGING
$(jq -r '.[]|select(.assignees=="" and .age>7)|"- UNASSIGNED (\(.age)d): \(.name)"' /tmp/triage.json | head -5)
$(jq -r ".[]|select(.age>$AGING_TASK_DAYS)|\"- AGING (\\(.age)d): \\(.name)\"" /tmp/triage.json | head -5)
REOF

cat /tmp/triage-report.md
```

### Step 7: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
BODY=$(cat /tmp/triage-report.md | tail -n +3)  # skip markdown title
slack_post "$SLACK_ENGINEERING" "Backlog Health — $(date +%Y-%m-%d)" "$BODY" "pm-backlog-triage"
```
