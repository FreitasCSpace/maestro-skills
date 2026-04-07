# Step 1: Find Ended Sprint + Guard Checks → /tmp/retro-sprint.json

Target sprint = the one whose due_date <= now and is closest to now (most recently ended non-done sprint).
Writes /tmp/retro-skip sentinel if no eligible sprint — downstream steps check and return early.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select((.due_date // "0" | tonumber) > 0)
        | select((.due_date | tonumber) <= $now)
      ]
      | sort_by(.due_date | tonumber)
      | last
      | {id, name, status: .status.status,
         due_ms: (.due_date | tonumber),
         start_ms: (.start_date // "0" | tonumber)}
    ' > /tmp/retro-sprint.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/retro-sprint.json)
SPRINT_NAME=$(jq -r '.name // "unknown"' /tmp/retro-sprint.json)
RETRO_TAG="retro-${SPRINT_ID}"

if [ -z "$SPRINT_ID" ]; then
  echo "No ended sprint found — skipping"
  touch /tmp/retro-skip; return 0
fi

echo "Sprint ended: $SPRINT_NAME (id: $SPRINT_ID, tag: $RETRO_TAG)"
```
