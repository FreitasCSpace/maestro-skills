# Step 8: Post Sync Summary to Standup Channel

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sync-sprint.json)

UPDATES=$(jq  '[.[] | select(.type=="status_update")] | length' /tmp/sync-actions.json)
NEW_TASKS=$(jq '[.[] | select(.type=="new_task")]     | length' /tmp/sync-actions.json)
PINGED=$(jq  length /tmp/sync-pings-sent.json)
REPLIED=$(jq length /tmp/sync-replies.json)

UPDATE_LINES=$(jq -r '
  .[] | select(.type=="status_update") |
  "• \(.task_name): \(.old_status) → \(.new_status) (\(.assignee))"
' /tmp/sync-actions.json | head -10)

NEW_LINES=$(jq -r '
  .[] | select(.type=="new_task") |
  "• 🆕 \(.task_name) (\(.assignee))"
' /tmp/sync-actions.json)

{
  printf '🐕 *Snoop Sync Complete — %s* 🎵\n\n' "$SPRINT_NAME"
  printf '📤 Pinged: %s | 💬 Replied: %s | 🔥 Updates: %s | 🆕 New: %s\n\n' \
    "$PINGED" "$REPLIED" "$UPDATES" "$NEW_TASKS"
  [ -n "$UPDATE_LINES" ] && printf '*Status Updates*\n%s\n\n' "$UPDATE_LINES"
  [ -n "$NEW_LINES"    ] && printf '*New Joints*\n%s\n\n' "$NEW_LINES"
  printf '_Keep it real and update yo tasks, cuz! — Snoop D-O-double-G 🐕💨_\n'
} > /tmp/sync-summary.md

BODY=$(cat /tmp/sync-summary.md)
slack_post "$SLACK_STANDUP" "🐕 Snoop Sync — $SPRINT_NAME" "$BODY" "pm-status-sync"
```
