# Step 5: Move Candidates to Sprint → /tmp/finalize-log.txt

Links each candidate to the sprint list via `cu_api`. Tags with `sprint-finalized-{sprint-id}` via `cu_api`.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-state.json)
FINALIZE_TAG="sprint-finalized-${SPRINT_ID}"
> /tmp/finalize-log.txt

jq -r '.[] | @base64' /tmp/candidates.json \
| while IFS= read -r row; do
  ID=$(echo "$row"   | base64 -d | jq -r '.id')
  NAME=$(echo "$row" | base64 -d | jq -r '.name')
  SP=$(echo "$row"   | base64 -d | jq -r '.sp')

  cu_api POST "list/$SPRINT_ID/task/$ID" '{}' > /dev/null
  cu_api POST "task/$ID/tag/$FINALIZE_TAG" '{}' > /dev/null

  echo "MOVED: $NAME (${SP}SP)" >> /tmp/finalize-log.txt
  sleep 0.3
done

echo "=== Move Summary ===" >> /tmp/finalize-log.txt
echo "Total moved: $(grep -c "^MOVED:" /tmp/finalize-log.txt)" >> /tmp/finalize-log.txt
cat /tmp/finalize-log.txt
```
