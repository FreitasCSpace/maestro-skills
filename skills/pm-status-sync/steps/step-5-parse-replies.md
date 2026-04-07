# Step 5: Parse Structured Replies → /tmp/sync-actions.json

Parses the structured template format. No AI needed — line-by-line regex matching.

**Status keyword map:**
- `done / finished / merged / closed / completed` → `closed`
- `in progress / working / started / active` → `in progress`
- `blocked / stuck / waiting` → `blocked`
- `review / reviewing / pr open / in review` → `review`

**Task name matching:** case-insensitive substring match against `/tmp/sync-tasks.json`.

```bash
source ~/.claude/skills/_pm-shared/context.sh

jq -n '[]' > /tmp/sync-actions.json

jq -r '.[] | [.id, .name_lower, .status, .url] | @tsv' /tmp/sync-tasks.json \
  > /tmp/sync-task-index.tsv

map_status() {
  local raw=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | xargs)
  case "$raw" in
    *done*|*finished*|*merged*|*closed*|*completed*) echo "closed" ;;
    *in\ progress*|*working*|*started*|*active*)     echo "in progress" ;;
    *blocked*|*stuck*|*waiting*)                     echo "blocked" ;;
    *review*|*reviewing*|*pr\ open*|*in\ review*)    echo "review" ;;
    *) echo "$raw" ;;
  esac
}

find_task_id() {
  local needle=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  awk -F'\t' -v n="$needle" \
    'BEGIN{best="";bestid=""} $2==n{print $1; exit} index($2,n)>0{bestid=$1;best=$2} END{print bestid}' \
    /tmp/sync-task-index.tsv | head -1
}

find_task_status() {
  local id="$1"
  awk -F'\t' -v i="$id" '$1==i{print $3}' /tmp/sync-task-index.tsv | head -1
}

find_task_url() {
  local id="$1"
  awk -F'\t' -v i="$id" '$1==i{print $4}' /tmp/sync-task-index.tsv | head -1
}

while IFS= read -r user_block; do
  ASSIGNEE=$(echo "$user_block" | jq -r '.assignee')

  ALL_TEXT=$(echo "$user_block" | jq -r '.replies[].text' | tr '\n' '\n')

  BLOCK=$(echo "$ALL_TEXT" | awk '/^---.*your update/{found=1; next} found && /^---/{exit} found{print}')
  [ -z "$BLOCK" ] && BLOCK="$ALL_TEXT"

  while IFS= read -r line; do
    line=$(echo "$line" | xargs)
    [ -z "$line" ] && continue

    if echo "$line" | grep -qiE '^new:'; then
      TASK_NAME=$(echo "$line" | sed 's/^new://i' | awk -F'—' '{print $1}' | xargs)
      DESCRIPTION=$(echo "$line" | awk -F'—' '{print $2}' | xargs)
      jq --arg a "$ASSIGNEE" --arg n "$TASK_NAME" --arg d "${DESCRIPTION:-$TASK_NAME}" \
        '. += [{type:"new_task", task_name:$n, description:$d, assignee:$a,
                status:"in progress", needs_github_issue:true}]' \
        /tmp/sync-actions.json > /tmp/sync-actions.tmp \
        && mv /tmp/sync-actions.tmp /tmp/sync-actions.json
      echo "NEW: $ASSIGNEE — $TASK_NAME"
      continue
    fi

    if echo "$line" | grep -qE '^[^:]+:'; then
      TASK_RAW=$(echo "$line" | awk -F':' '{print $1}' | xargs)
      REST=$(echo "$line" | cut -d: -f2- | xargs)
      STATUS_RAW=$(echo "$REST" | awk -F'—' '{print $1}' | xargs)
      NOTE=$(echo "$REST" | awk -F'—' '{print $2}' | xargs)
      NEW_STATUS=$(map_status "$STATUS_RAW")
      TASK_ID=$(find_task_id "$TASK_RAW")

      if [ -n "$TASK_ID" ]; then
        OLD_STATUS=$(find_task_status "$TASK_ID")
        TASK_URL=$(find_task_url "$TASK_ID")
        jq --arg a "$ASSIGNEE" --arg id "$TASK_ID" \
           --arg tn "$TASK_RAW" --arg os "$OLD_STATUS" \
           --arg ns "$NEW_STATUS" --arg note "$NOTE" --arg url "$TASK_URL" \
          '. += [{type:"status_update", task_id:$id, task_name:$tn,
                  old_status:$os, new_status:$ns, comment:$note,
                  assignee:$a, url:$url}]' \
          /tmp/sync-actions.json > /tmp/sync-actions.tmp \
          && mv /tmp/sync-actions.tmp /tmp/sync-actions.json
        echo "UPDATE: $ASSIGNEE — $TASK_RAW → $NEW_STATUS"
      else
        echo "WARN: no task match for '$TASK_RAW' ($ASSIGNEE) — skipping"
      fi
    fi
  done <<< "$BLOCK"

done < <(jq -c '.[]' /tmp/sync-replies.json)

echo "=== Actions parsed ==="
echo "Status updates: $(jq '[.[]|select(.type=="status_update")]|length' /tmp/sync-actions.json)"
echo "New tasks:      $(jq '[.[]|select(.type=="new_task")]|length'      /tmp/sync-actions.json)"
```
