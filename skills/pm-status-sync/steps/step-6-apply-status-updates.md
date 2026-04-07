# Step 6: Apply Status Updates to ClickUp ⚠️ HITL-gated

**Show this summary and wait for approval before applying:**

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "🐕 Yo here's what we about to do, big homie:"
echo ""
echo "Status Updates:"
jq -r '.[] | select(.type=="status_update") |
  "  \(.old_status) → \(.new_status)  \(.task_name) (\(.assignee))\(if .comment != "" then " — \"\(.comment)\"" else "" end)"
' /tmp/sync-actions.json

echo ""
echo "New Joints:"
jq -r '.[] | select(.type=="new_task") |
  "  🆕 \(.task_name) (\(.assignee)) — \(.description)"
' /tmp/sync-actions.json

echo ""
echo "Approve these moves? (operator confirms before continuing)"
```

After HITL approval, apply updates:

```bash
source ~/.claude/skills/_pm-shared/context.sh

map_cu_status() {
  case "$1" in
    "closed")      echo "closed" ;;
    "in progress") echo "in progress" ;;
    "blocked")     echo "blocked" ;;
    "review")      echo "review" ;;
    *)             echo "$1" ;;
  esac
}

> /tmp/sync-apply-log.txt

while IFS= read -r action; do
  TASK_ID=$(echo "$action"   | jq -r '.task_id')
  TASK_NAME=$(echo "$action" | jq -r '.task_name')
  NEW_STATUS=$(echo "$action"| jq -r '.new_status')
  COMMENT=$(echo "$action"   | jq -r '.comment // ""')
  ASSIGNEE=$(echo "$action"  | jq -r '.assignee')
  CU_STATUS=$(map_cu_status "$NEW_STATUS")

  RESULT=$(cu_api PUT "task/$TASK_ID" \
    "$(jq -n --arg s "$CU_STATUS" '{status:$s}')")
  if echo "$RESULT" | jq -e '.id' > /dev/null 2>&1; then
    echo "UPDATED: $TASK_NAME → $CU_STATUS" >> /tmp/sync-apply-log.txt
  else
    echo "ERROR: $TASK_NAME — $(echo "$RESULT" | jq -r '.err // "unknown"')" >> /tmp/sync-apply-log.txt
  fi

  if [ -n "$COMMENT" ] && [ "$COMMENT" != "null" ]; then
    cu_api POST "task/$TASK_ID/comment" \
      "$(jq -n --arg c "[🐕 Snoop Sync — $ASSIGNEE] $COMMENT" '{comment_text:$c}')" \
      > /dev/null
  fi
  sleep 0.3
done < <(jq -c '.[] | select(.type=="status_update")' /tmp/sync-actions.json)

cat /tmp/sync-apply-log.txt
```
