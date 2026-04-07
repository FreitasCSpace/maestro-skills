# Step 2: Fetch Tasks + Idempotency Check → /tmp/retro-tasks.json

Paginated. SP stored as number. Idempotency tag is `retro-{sprint-id}` — stable across re-runs on different days.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/retro-sprint.json)
RETRO_TAG="retro-${SPRINT_ID}"

> /tmp/retro-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/retro-page.json
  COUNT=$(jq '.tasks | length' /tmp/retro-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/retro-page.json >> /tmp/retro-pages.ndjson
  echo >> /tmp/retro-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:70],
      status: (.status.status | ascii_downcase),
      assignees: [.assignees[].username],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      tags: [.tags[].name]
    }
  ]' /tmp/retro-pages.ndjson > /tmp/retro-tasks.json

TOTAL=$(jq length /tmp/retro-tasks.json)
echo "Total tasks: $TOTAL"

if [ "$TOTAL" -eq 0 ]; then
  echo "Empty sprint — skipping"
  touch /tmp/retro-skip; return 0
fi

# Idempotency: check for retro-{sprint-id} tag on any task
ALREADY=$(jq --arg t "$RETRO_TAG" '[.[] | select(.tags | any(. == $t))] | length' /tmp/retro-tasks.json)
if [ "$ALREADY" -gt 0 ]; then
  echo "Retro already ran for sprint $SPRINT_ID ($ALREADY tasks tagged) — skipping"
  touch /tmp/retro-skip; return 0
fi
echo "No retro tag found — proceeding"
```
