# Step 2: Check Sprint State (active vs empty) → /tmp/sprint-current-tasks.json

Saves response to file before branching — prevents silent failure on API error.
If sprint has tasks → report-only mode (Step 2a). If empty → proceed to planning (Step 3).

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)

cu_api GET "list/$SPRINT_ID/task?include_closed=false&subtasks=true&page=0" \
  > /tmp/sprint-current-tasks.json

TASK_COUNT=$(jq '.tasks | length' /tmp/sprint-current-tasks.json)

if [ -z "$TASK_COUNT" ] || [ "$TASK_COUNT" = "null" ]; then
  echo "ERROR: could not fetch sprint tasks — check CLICKUP_PERSONAL_TOKEN and SPRINT_ID=$SPRINT_ID"
  touch /tmp/planner-skip; return 0
fi

echo "Sprint current tasks: $TASK_COUNT"

if [ "$TASK_COUNT" -gt 0 ]; then
  echo "ACTIVE_SPRINT" > /tmp/planner-mode.txt
else
  echo "EMPTY_SPRINT"  > /tmp/planner-mode.txt
fi
```
