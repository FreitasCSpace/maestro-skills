---
name: pm-backlog-triage
description: Import GitHub issues into ClickUp backlog, deduplicate, normalize priorities, estimate story points, triage, and post health report to Slack. Idempotent — safe to run repeatedly.
---

# PM Backlog Triage

**Fully autonomous. Idempotent. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Delete ClickUp tasks whose linked GitHub issue no longer exists (404/closed) — no cap
- Max per run: 50 creates, 50 SP updates, 100 GH comment upserts
- Only set SP on tasks with zero SP — never overwrite
- Never set priority to urgent unless tagged security/compliance
- Idempotency:
  - URL dedup prevents re-importing the same GH issue
  - **GH bot comment is upserted, never appended** — exactly ONE bot comment per issue, marked `<!-- pm-bot:clickup-link v1 -->`. If the ClickUp URL changes, the existing comment is PATCHed. Duplicates are deleted.
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
> /tmp/cu-pages.ndjson
PAGE=0; MAX_PAGES=20
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$LIST_MASTER_BACKLOG/task?include_closed=false&subtasks=true&page=$PAGE" > /tmp/cu-page.json
  COUNT=$(jq '.tasks | length' /tmp/cu-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/cu-page.json >> /tmp/cu-pages.ndjson
  echo >> /tmp/cu-pages.ndjson
  PAGE=$((PAGE + 1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

# Aggregate all pages into one task array
jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:80],
      desc: (.description // ""),
      tags: [.tags[].name],
      pri: (.priority.priority // "4"),
      sp: (((.custom_fields[]? | select(.id==$cf) | .value) // 0) | tostring),
      age: (((now - ((.date_created|tonumber)/1000))/86400) | floor),
      assignees: [.assignees[].username]
  } ]' /tmp/cu-pages.ndjson > /tmp/cu-backlog.json

# Build URL index for dedup (parse desc field, not raw JSON)
jq -r '.[].desc' /tmp/cu-backlog.json \
  | grep -oP 'https://github\.com/[^/]+/[^/]+/issues/\d+' \
  | sort -u > /tmp/cu-urls.txt

echo "ClickUp backlog tasks: $(jq length /tmp/cu-backlog.json)"
echo "Known GitHub URLs: $(wc -l < /tmp/cu-urls.txt)"
```

### Step 3: Batch-Validate GH↔CU Links (GraphQL) → /tmp/stale-issues-log.txt

Build the canonical CU↔GH map from Step 2's cache (includes pri/sp/domain for rich comments).
Use **GraphQL batch** (~50 issues per API call).
- GH issue **404/NOTFOUND** → DELETE CU task (it's a ghost)
- GH issue **CLOSED** → set CU status to `closed` (keeps history, doesn't delete)

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/stale-issues-log.txt
# cu-gh-map.tsv: cu_id<TAB>repo<TAB>num<TAB>cu_url<TAB>pri<TAB>sp<TAB>domain
> /tmp/cu-gh-map.tsv
> /tmp/gh-check-input.tsv
DELETED=0; CLOSED_CU=0

# Extract CU task → GH map, include pri/sp/domain for downstream rich comments
jq -r '
  .[] | . as $t
  | ($t.desc | scan("https://github\\.com/([^/]+/[^/]+)/issues/([0-9]+)")) as $m
  | [ $t.id, $m[0], $m[1],
      "https://app.clickup.com/t/\($t.id)",
      ($t.pri // "4"),
      ($t.sp  // "0"),
      (($t.tags | map(select(. == "frontend" or . == "backend" or . == "mobile"
                             or . == "infra" or . == "ai-cv" or . == "sdk"
                             or . == "bots" or . == "video")) | first) // "other")
    ]
  | @tsv
' /tmp/cu-backlog.json > /tmp/cu-gh-map.tsv

awk -F'\t' '{print $2"\t"$3}' /tmp/cu-gh-map.tsv | sort -u > /tmp/gh-check-input.tsv
TOTAL_CHECK=$(wc -l < /tmp/gh-check-input.tsv)
echo "Batch-checking $TOTAL_CHECK unique GH issues via GraphQL..."

# /tmp/gh-states.tsv: repo<TAB>num<TAB>state<TAB>url
gh_batch_states /tmp/gh-check-input.tsv /tmp/gh-states.tsv

# Split into: ghosts (404) and closed (done on GH)
awk -F'\t' '
  NR==FNR { st[$1"|"$2]=$3; next }
  {
    key=$2"|"$3; s=st[key]
    if (s=="" || s=="NOTFOUND") print $0 > "/tmp/cu-ghost.tsv"
    else if (s=="CLOSED")       print $0 > "/tmp/cu-closed.tsv"
  }
' /tmp/gh-states.tsv /tmp/cu-gh-map.tsv

# Hard-delete ghost tasks (GH issue no longer exists)
while IFS=$'\t' read -r cu_id repo num rest; do
  cu_api DELETE "task/$cu_id" > /dev/null
  echo "DELETED (ghost): $cu_id → $repo#$num" >> /tmp/stale-issues-log.txt
  DELETED=$((DELETED+1)); sleep 0.2
done < /tmp/cu-ghost.tsv

# Close CU tasks for issues closed on GitHub (preserve history)
while IFS=$'\t' read -r cu_id repo num rest; do
  cu_api PUT "task/$cu_id" '{"status":"closed"}' > /dev/null
  echo "CLOSED (gh-closed): $cu_id → $repo#$num" >> /tmp/stale-issues-log.txt
  CLOSED_CU=$((CLOSED_CU+1)); sleep 0.2
done < /tmp/cu-closed.tsv

TOTAL_MAP=$(wc -l < /tmp/cu-gh-map.tsv)
VALID=$(( TOTAL_MAP - DELETED - CLOSED_CU ))
echo "=== Stale Issue Cleanup ===" >> /tmp/stale-issues-log.txt
echo "Mapped: $TOTAL_MAP | Valid: $VALID | Closed: $CLOSED_CU | Deleted: $DELETED" >> /tmp/stale-issues-log.txt
cat /tmp/stale-issues-log.txt

# Remove ghost + closed tasks from the live map (don't backfill comments on dead tasks)
cat /tmp/cu-ghost.tsv /tmp/cu-closed.tsv 2>/dev/null \
  | awk -F'\t' 'NR==FNR{skip[$1]=1; next} !skip[$1]' - /tmp/cu-gh-map.tsv \
  > /tmp/cu-gh-map.live.tsv
mv /tmp/cu-gh-map.live.tsv /tmp/cu-gh-map.tsv
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

  # Set SP via custom field, assign lead, post bot comment on GH issue
  CMT="skipped"
  if [ "$RES" != "ERROR" ] && [ -n "$RES" ]; then
    cu_api POST "task/$RES/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null

    if [ -n "$LEAD" ]; then
      ASSIGN_PAYLOAD=$(jq -n --argjson uid "$LEAD" '{assignees:{add:[$uid]}}')
      cu_api PUT "task/$RES" "$ASSIGN_PAYLOAD" > /dev/null
    fi

    # Post the canonical bot comment on the GH issue (rich format)
    CU_URL="https://app.clickup.com/t/$RES"
    CMT=$(gh_upsert_clickup_comment "$GITHUB_ORG/$repo" "$num" "$CU_URL" "$PRI" "$SP" "$domain")
    # Track the new pair for downstream backfill (skips it in Step 5 — already handled)
    printf '%s\t%s/%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$RES" "$GITHUB_ORG" "$repo" "$num" "$CU_URL" "$PRI" "$SP" "$domain" \
      >> /tmp/cu-gh-map.tsv
  fi

  echo "IMPORT $repo#$num → $RES (pri=$PRI, sp=$SP, domain=$domain, gh-comment=$CMT)" >> /tmp/import-log.txt
  COUNT=$((COUNT+1)); IMPORTED=$((IMPORTED+1)); sleep 0.3
done < /tmp/new-issues.tsv

echo "Imported: $IMPORTED" >> /tmp/import-log.txt
cat /tmp/import-log.txt
```

### Step 5: Backfill / Repair GH Bot Comments → /tmp/comment-log.txt

For every CU↔GH pair (live, post-cleanup), ensure the GH issue has **exactly one** bot comment pointing to the **current** ClickUp URL. Fixes invalid links from previous runs and dedupes any stragglers.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/comment-log.txt
CREATED=0; UPDATED=0; DEDUPED=0; NOCHANGE=0; MAX_COMMENTS=100

# cu-gh-map.tsv format: cu_id<TAB>repo<TAB>num<TAB>cu_url<TAB>pri<TAB>sp<TAB>domain
# `repo` is always "owner/name" — Step 3 extraction and Step 4 import both write full path
COUNT=0
while IFS=$'\t' read -r cu_id repo num cu_url pri sp domain; do
  [ $COUNT -ge $MAX_COMMENTS ] && echo "HIT MAX_COMMENTS=$MAX_COMMENTS" >> /tmp/comment-log.txt && break
  [ -z "$cu_id" ] || [ -z "$num" ] && continue

  result=$(gh_upsert_clickup_comment "$repo" "$num" "$cu_url" "$pri" "$sp" "$domain")
  echo "$result $full_repo#$num → $cu_url" >> /tmp/comment-log.txt
  case "$result" in
    created)  CREATED=$((CREATED+1)) ;;
    updated)  UPDATED=$((UPDATED+1)) ;;
    deduped)  DEDUPED=$((DEDUPED+1)) ;;
    nochange) NOCHANGE=$((NOCHANGE+1)) ;;
  esac
  COUNT=$((COUNT+1))
  sleep 0.2
done < /tmp/cu-gh-map.tsv

echo "=== Comment Sync ===" >> /tmp/comment-log.txt
echo "created=$CREATED updated=$UPDATED deduped=$DEDUPED nochange=$NOCHANGE" >> /tmp/comment-log.txt
tail -3 /tmp/comment-log.txt
```

### Step 6: Estimate Missing SP → /tmp/sp-log.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/sp-log.txt

# Reuse backlog from Step 2 — ClickUp returns SP as a STRING; coerce before compare
jq '[.[] | select((.sp|tostring) == "0" or (.sp|tostring) == "" or .sp == null)
       | {id, name: .name[0:60], tags}]' \
  /tmp/cu-backlog.json > /tmp/no-sp.json

TOTAL=$(jq length /tmp/no-sp.json)
echo "Tasks missing SP: $TOTAL" | tee /tmp/sp-log.txt
COUNT=0; MAX=50

for row in $(jq -r '.[] | @base64' /tmp/no-sp.json); do
  [ $COUNT -ge $MAX ] && break
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  TAGS=$(echo "$row"|base64 -d|jq -r '.tags|join(",")')

  # SP estimation heuristic — first match wins, no overwrites
  SP=2  # default
  case "$TAGS" in
    *security*|*compliance*) SP=8;;
    *bug*)
      if echo "$NAME" | grep -qiE "critical|crash|data.loss"; then SP=8; else SP=5; fi;;
    *feature*|*enhancement*)
      if   echo "$NAME" | grep -qiE "refactor|rewrite|migrate|redesign"; then SP=21
      elif echo "$NAME" | grep -qiE "add|create|new|implement";          then SP=13
      else SP=5; fi;;
    *infra*|*ci*|*config*) SP=3;;
  esac

  cu_api POST "task/$ID/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null
  echo "SP: $NAME → ${SP}" >> /tmp/sp-log.txt
  COUNT=$((COUNT+1)); sleep 0.2
done

echo "SP set: $COUNT" >> /tmp/sp-log.txt
tail -5 /tmp/sp-log.txt
```

### Step 7: Triage Report → /tmp/triage-report.md

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Reuse the paginated backlog cache from Step 2 (already has age + assignees)
jq '[.[] | {name, pri, assignees: (.assignees|join(",")), age, tags}]' \
  /tmp/cu-backlog.json > /tmp/triage.json

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
$(tail -3 /tmp/import-log.txt)
$(tail -1 /tmp/comment-log.txt)
$(tail -1 /tmp/sp-log.txt)
$(tail -1 /tmp/stale-issues-log.txt)

## Needs Attention
- Unassigned >7d: $UNASSIGNED
- Stale >${STALE_TASK_DAYS}d: $STALE
- Aging >${AGING_TASK_DAYS}d: $AGING
$(jq -r '.[]|select(.assignees=="" and .age>7)|"- UNASSIGNED (\(.age)d): \(.name)"' /tmp/triage.json | head -5)
$(jq -r ".[]|select(.age>$AGING_TASK_DAYS)|\"- AGING (\\(.age)d): \\(.name)\"" /tmp/triage.json | head -5)
REOF

cat /tmp/triage-report.md
```

### Step 8: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
BODY=$(cat /tmp/triage-report.md | tail -n +3)  # skip markdown title
slack_post "$SLACK_ENGINEERING" "Backlog Health — $(date +%Y-%m-%d)" "$BODY" "pm-backlog-triage"
```
