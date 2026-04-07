# Step 5: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
BODY=$(tail -n +3 /tmp/retro-report.md)   # skip markdown title
slack_post "$SLACK_SPRINT" "Sprint Retro: $SPRINT_NAME" "$BODY" "pm-retrospective"
```
