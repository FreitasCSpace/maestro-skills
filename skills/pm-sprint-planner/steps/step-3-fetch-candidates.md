# Step 3: Fetch Sprint Candidates (Paginated) → /tmp/candidates.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)
FINALIZE_TAG="sprint-finalized-${SPRINT_ID}"

> /tmp/cand-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$LIST_SPRINT_CANDIDATES/task?include_closed=false&subtasks=true&page=$PAGE" \
    > /tmp/cand-page.json
  COUNT=$(jq '.tasks | length' /tmp/cand-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/cand-page.json >> /tmp/cand-pages.ndjson
  echo >> /tmp/cand-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:70],
      assignees: [.assignees[].username],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      tags: [.tags[].name]
    }
  ]
  | sort_by((.pri | tonumber), -.sp)
' /tmp/cand-pages.ndjson > /tmp/candidates.json

CAND_COUNT=$(jq 'length' /tmp/candidates.json)
echo "Candidates: $CAND_COUNT tasks"

if [ "$CAND_COUNT" -eq 0 ]; then
  echo "No candidates — team needs to add tasks to Sprint Candidates list"
  slack_post "$SLACK_SPRINT" "Sprint Planner: No Candidates" \
    "Sprint Candidates list is empty. Add tasks before running the planner." "pm-sprint-planner"
  touch /tmp/planner-skip; return 0
fi

ALREADY=$(jq --arg t "$FINALIZE_TAG" '[.[] | select(.tags | any(. == $t))] | length' /tmp/candidates.json)
if [ "$ALREADY" -gt 0 ]; then
  echo "Already finalized for sprint $SPRINT_ID ($ALREADY tasks tagged) — skipping"
  touch /tmp/planner-skip; return 0
fi
echo "No finalization tag found — proceeding"
```
