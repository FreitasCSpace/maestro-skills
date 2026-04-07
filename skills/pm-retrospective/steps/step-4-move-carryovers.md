# Step 4: Move Carryovers + Tag All Tasks

Links carryovers to Sprint Candidates list. Priority bump capped at 2 (High) unless security/compliance.
All tasks tagged `retro-{sprint-id}` via `cu_api` for reliable retry logic.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

RETRO_TAG="retro-$(jq -r '.id' /tmp/retro-sprint.json)"
SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
> /tmp/retro-move-log.txt

jq -r '.[] | select(.status | test("complete|done|closed|resolved") | not) | @base64' \
  /tmp/retro-tasks.json \
| while IFS= read -r row; do
  ID=$(echo "$row"   | base64 -d | jq -r '.id')
  NAME=$(echo "$row" | base64 -d | jq -r '.name')
  PRI=$(echo "$row"  | base64 -d | jq -r '.pri')
  TAGS=$(echo "$row" | base64 -d | jq -r '.tags | join(",")')

  case "$PRI" in
    4) NEWPRI=3 ;;
    3) NEWPRI=2 ;;
    2) echo "$TAGS" | grep -qiE "security|compliance" && NEWPRI=1 || NEWPRI=2 ;;
    *) NEWPRI=$PRI ;;
  esac

  cu_api POST "list/$LIST_SPRINT_CANDIDATES/task/$ID" '{}' > /dev/null
  cu_api PUT "task/$ID" "{\"priority\":$NEWPRI}" > /dev/null
  cu_api POST "task/$ID/tag/carryover" '{}' > /dev/null

  COMMENT=$(jq -n --arg sprint "$SPRINT_NAME" --arg op "$PRI" --arg np "$NEWPRI" --arg date "$(date +%Y-%m-%d)" \
    '{comment_text: "Carried over from \($sprint). Priority bumped \($op)→\($np). — PM Bot \($date)"}')
  cu_api POST "task/$ID/comment" "$COMMENT" > /dev/null

  echo "MOVED: $NAME (pri $PRI→$NEWPRI)" >> /tmp/retro-move-log.txt
  sleep 0.3
done

jq -r '.[] | select(.status | test("complete|done|closed|resolved") | not) | .id' \
  /tmp/retro-tasks.json \
| while IFS= read -r task_id; do
  cu_api POST "task/$task_id/tag/$RETRO_TAG" '{}' > /dev/null
  sleep 0.1
done

echo "=== Carryover Summary ===" >> /tmp/retro-move-log.txt
cat /tmp/retro-move-log.txt
```
