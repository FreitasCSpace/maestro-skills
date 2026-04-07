# Step 3: Batch-Validate GH↔CU Links (GraphQL) → /tmp/stale-issues-log.txt

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
