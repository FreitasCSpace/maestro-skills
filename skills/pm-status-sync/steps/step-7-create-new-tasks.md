# Step 7: Create New Tasks + GitHub Issues ⚠️ HITL-gated

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sync-sprint.json)
> /tmp/sync-create-log.txt

while IFS= read -r action; do
  TASK_NAME=$(echo "$action"  | jq -r '.task_name')
  DESCRIPTION=$(echo "$action"| jq -r '.description')
  ASSIGNEE=$(echo "$action"   | jq -r '.assignee')
  STATUS=$(echo "$action"     | jq -r '.status')
  NEEDS_ISSUE=$(echo "$action"| jq -r '.needs_github_issue')

  ISSUE_URL=""
  if [ "$NEEDS_ISSUE" = "true" ]; then
    DOMAIN=$(jq -r --arg u "$ASSIGNEE" \
      'to_entries[] | select(.value==$u) | .key' /tmp/clickup-user-map.json | head -1)
    REPO=$(awk -v d="$DOMAIN" -F'"' '
      /\[.*\]=/ { key=$2 }
      /=/ && key==d { split($0,a,"\""); print a[2]; exit }
    ' /dev/null 2>/dev/null || echo "carespace-admin")

    ISSUE_RESP=$(gh issue create \
      --repo "$GITHUB_ORG/$REPO" \
      --title "$TASK_NAME" \
      --body "$(printf '## Context\n\n%s\n\n---\n*Created by Snoop Dogg PM Bot 🐕 from status update by @%s*' \
                "$DESCRIPTION" "$ASSIGNEE")" 2>&1)
    ISSUE_URL=$(echo "$ISSUE_RESP" | grep -oP 'https://github\.com/\S+' | head -1)
    echo "GH issue: $ISSUE_URL" >> /tmp/sync-create-log.txt
  fi

  CU_ASSIGNEE_ID=$(jq -r --arg u "$ASSIGNEE" '.[$u] // empty' /tmp/clickup-user-map.json)
  DESC="${DESCRIPTION}${ISSUE_URL:+\n\nGitHub: $ISSUE_URL}"

  PAYLOAD=$(jq -n \
    --arg name "$TASK_NAME" \
    --arg desc "$DESC" \
    --arg status "$STATUS" \
    --argjson assignees "$([ -n "$CU_ASSIGNEE_ID" ] && echo "[$CU_ASSIGNEE_ID]" || echo '[]')" \
    '{name:$name, description:$desc, status:$status, assignees:$assignees}')

  RESULT=$(cu_api POST "list/$SPRINT_ID/task" "$PAYLOAD")
  TASK_ID=$(echo "$RESULT" | jq -r '.id // "ERROR"')
  echo "CREATED: $TASK_NAME → $TASK_ID" >> /tmp/sync-create-log.txt
  sleep 0.3
done < <(jq -c '.[] | select(.type=="new_task")' /tmp/sync-actions.json)

cat /tmp/sync-create-log.txt
```
