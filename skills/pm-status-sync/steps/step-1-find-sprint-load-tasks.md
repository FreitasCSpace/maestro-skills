# Step 1: Find Active Sprint + Load Tasks → /tmp/sync-sprint.json, /tmp/sync-tasks.json

Active sprint = non-done list with `start_date <= now < due_date`.
Paginated task fetch. Uses `date_updated` for staleness.

```bash
source ~/.claude/skills/_pm-shared/context.sh

NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select((.start_date // "0" | tonumber) <= $now)
        | select((.due_date   // "9999999999999" | tonumber) > $now)
      ]
      | sort_by(.start_date // "0" | tonumber)
      | last
      // ([ .lists[] | select(.status.status != "done") ]
          | sort_by(.start_date // "0" | tonumber) | last)
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' > /tmp/sync-sprint.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sync-sprint.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sync-sprint.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO ACTIVE SPRINT — stopping"
  return 0 2>/dev/null; exit 0
fi
echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"

> /tmp/sync-task-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/sync-page.json
  COUNT=$(jq '.tasks | length' /tmp/sync-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/sync-page.json >> /tmp/sync-task-pages.ndjson
  echo >> /tmp/sync-task-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:80],
      name_lower: (.name | ascii_downcase),
      status: (.status.status | ascii_downcase),
      assignees: [.assignees[].username],
      assignee_ids: [.assignees[].id | tostring],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      updated_ms: (.date_updated // "0" | tonumber),
      url
    }
  ]' /tmp/sync-task-pages.ndjson > /tmp/sync-tasks.json

echo "Sprint tasks: $(jq length /tmp/sync-tasks.json)"
```
