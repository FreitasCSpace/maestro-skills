# Step 2a: Active Sprint — Status Report Only

Only runs if sprint already has tasks. Read-only. Posts status to Slack, then sets skip sentinel.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && return 0
[ "$(cat /tmp/planner-mode.txt 2>/dev/null)" != "ACTIVE_SPRINT" ] && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-state.json)
DUE_FMT=$(date -d "@$(( DUE_MS / 1000 ))" +%Y-%m-%d 2>/dev/null || echo "no due date")
TASK_COUNT=$(jq '.tasks | length' /tmp/sprint-current-tasks.json)

> /tmp/cand-pages.ndjson
PAGE=0
while [ $PAGE -lt 5 ]; do
  cu_api GET "list/$LIST_SPRINT_CANDIDATES/task?include_closed=false&page=$PAGE" > /tmp/cand-page.json
  COUNT=$(jq '.tasks | length' /tmp/cand-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/cand-page.json >> /tmp/cand-pages.ndjson
  echo >> /tmp/cand-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done
CAND_COUNT=$(jq -s '[.[].tasks[]] | length' /tmp/cand-pages.ndjson 2>/dev/null || echo 0)

MSG="*${SPRINT_NAME}* — Active until ${DUE_FMT} | ${TASK_COUNT} tasks in sprint | ${CAND_COUNT} candidates queued for next sprint."
slack_post "$SLACK_SPRINT" "Sprint Status: $SPRINT_NAME" "$MSG" "pm-sprint-planner"
echo "Active sprint reported — planning skipped."
touch /tmp/planner-skip
```
