# Step 1: Find Target Sprint → /tmp/sprint-state.json

Target sprint = the earliest non-done sprint by start_date (upcoming or just started).
Writes sentinel and stops if no sprint found.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '
      [ .lists[] | select(.status.status != "done") ]
      | sort_by(.start_date // "0" | tonumber)
      | first
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' > /tmp/sprint-state.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-state.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-state.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO SPRINT FOUND — create one in ClickUp first"
  touch /tmp/planner-skip; return 0
fi

echo "Target sprint: $SPRINT_NAME (id: $SPRINT_ID)"
```
