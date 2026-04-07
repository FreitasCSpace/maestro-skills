# Step 2: Load ClickUp Backlog → /tmp/cu-backlog.json

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
      assignees: [.assignees[].username],
      parent: (.parent // null)
  } ]' /tmp/cu-pages.ndjson > /tmp/cu-backlog.json

# Build URL index for dedup (parse desc field, not raw JSON)
jq -r '.[].desc' /tmp/cu-backlog.json \
  | grep -oP 'https://github\.com/[^/]+/[^/]+/issues/\d+' \
  | sort -u > /tmp/cu-urls.txt

echo "ClickUp backlog tasks: $(jq length /tmp/cu-backlog.json)"
echo "Known GitHub URLs: $(wc -l < /tmp/cu-urls.txt)"
```
