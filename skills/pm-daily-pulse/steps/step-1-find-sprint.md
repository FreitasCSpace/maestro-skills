# Step 1: Find Active Sprint → /tmp/sprint-info.json

Active sprint = a list in FOLDER_SPRINTS whose `start_date <= now < due_date`.
Falls back to the most recently started non-done list if no exact date match.

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select(
            (.start_date // "0" | tonumber) <= $now
            and ((.due_date // "9999999999999" | tonumber) > $now)
          )
      ]
      | sort_by(.start_date // "0" | tonumber)
      | last
      // (
          [ .lists[] | select(.status.status != "done") ]
          | sort_by(.start_date // "0" | tonumber)
          | last
        )
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' \
  > /tmp/sprint-info.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-info.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-info.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO ACTIVE SPRINT — skipping digest"
  touch /tmp/no-sprint
  slack_post "$SLACK_STANDUP" "Daily Pulse — $(date +%Y-%m-%d)" \
    "No active sprint found. Digest skipped." "pm-daily-pulse"
else
  echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"
fi
```
