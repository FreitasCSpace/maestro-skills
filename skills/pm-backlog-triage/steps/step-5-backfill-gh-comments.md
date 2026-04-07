# Step 5: Backfill / Repair GH Bot Comments → /tmp/comment-log.txt

For every CU↔GH pair (live, post-cleanup), ensure the GH issue has **exactly one** bot comment
pointing to the **current** ClickUp URL. Fixes invalid links from previous runs and dedupes any stragglers.

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
