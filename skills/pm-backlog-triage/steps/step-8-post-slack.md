# Step 8: Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
BODY=$(cat /tmp/triage-report.md | tail -n +3)  # skip markdown title
slack_post "$SLACK_ENGINEERING" "Backlog Health — $(date +%Y-%m-%d)" "$BODY" "pm-backlog-triage"
```
