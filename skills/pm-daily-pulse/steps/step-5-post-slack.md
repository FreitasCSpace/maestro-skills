# Step 5: Post to Slack (idempotent)

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
BODY=$(tail -n +3 /tmp/sprint-health.md)   # skip markdown title line
slack_post "$SLACK_STANDUP" "Daily Pulse — $SPRINT_NAME — $(date +%Y-%m-%d)" "$BODY" "pm-daily-pulse"
```
