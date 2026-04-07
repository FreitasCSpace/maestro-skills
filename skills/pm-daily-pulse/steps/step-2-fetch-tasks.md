# Step 2: Fetch Sprint Tasks → /tmp/sprint-tasks.json

Paginated. SP stored as number. Uses `date_updated` (not comments) for staleness.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-info.json)

> /tmp/sprint-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/sprint-page.json
  COUNT=$(jq '.tasks | length' /tmp/sprint-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/sprint-page.json >> /tmp/sprint-pages.ndjson
  echo >> /tmp/sprint-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:70],
      desc: ((.description // "") | gsub("<[^>]+>"; "") | .[0:300]),
      status: (.status.status | ascii_downcase),
      assignees: [.assignees[].username],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      updated_ms: (.date_updated // "0" | tonumber),
      url
    }
  ]' /tmp/sprint-pages.ndjson > /tmp/sprint-tasks.json

echo "Sprint tasks: $(jq length /tmp/sprint-tasks.json)"
[ "$(jq length /tmp/sprint-tasks.json)" = "0" ] && \
  echo "WARNING: sprint exists but has 0 tasks — check ClickUp configuration"
```
