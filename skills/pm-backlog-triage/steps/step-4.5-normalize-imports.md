# Step 4.5: Normalize Bad-Named Imports → /tmp/normalize-log.txt

Scans CU backlog for tasks with the legacy `[carespace-*]` repo-prefix naming
(from older import runs) and renames them to `[TYPE] cleaned-title`. Also adds
the missing type tag (`bug`/`feature`/`task`/`security`) so Step 6's SP heuristic
can estimate them on the next run.

Idempotent — only touches tasks matching the bad pattern. Safe to re-run.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/normalize-log.txt
RENAMED=0; SCANNED=0; MAX=100

# Find tasks where name starts with [carespace-...] (legacy bot import format)
jq -r '
  .[] | select(.name | test("^\\[carespace-[^]]*\\]"))
       | [.id, .name, (.tags|join(","))] | @tsv
' /tmp/cu-backlog.json > /tmp/bad-named.tsv

BAD_COUNT=$(wc -l < /tmp/bad-named.tsv)
echo "Tasks with legacy [carespace-*] naming: $BAD_COUNT" | tee -a /tmp/normalize-log.txt

while IFS=$'\t' read -r cu_id name tags; do
  [ $SCANNED -ge $MAX ] && echo "HIT MAX $MAX scans" >> /tmp/normalize-log.txt && break
  SCANNED=$((SCANNED+1))

  # Strip the [carespace-xxx] prefix to get the raw title
  RAW=$(echo "$name" | sed -E 's/^\[carespace-[^]]*\][[:space:]]*//')

  # Detect type from raw title content
  case "$RAW" in
    Bug:*|BUG:*|bug:*)              TYPE="BUG";      TYPE_TAG="bug" ;;
    Feature:*|Feat:*|FEATURE:*)     TYPE="FEATURE";  TYPE_TAG="feature" ;;
    Security:*|SECURITY:*)          TYPE="SECURITY"; TYPE_TAG="security" ;;
    Chore:*|Task:*|TASK:*)          TYPE="TASK";     TYPE_TAG="task" ;;
    *)
      # Fallback: infer from existing tags
      if   echo "$tags" | grep -qiw "bug";      then TYPE="BUG";      TYPE_TAG="bug"
      elif echo "$tags" | grep -qiw "feature";  then TYPE="FEATURE";  TYPE_TAG="feature"
      elif echo "$tags" | grep -qiw "security"; then TYPE="SECURITY"; TYPE_TAG="security"
      else                                           TYPE="TASK";     TYPE_TAG="task"
      fi ;;
  esac

  # Strip the trailing "Bug:" / "Feature:" prefix from raw title
  CLEAN=$(echo "$RAW" | sed -E 's/^(Bug|Feature|Feat|Task|Security|Chore):[[:space:]]*//i')
  NEW_NAME="[$TYPE] $CLEAN"

  # Skip if already correct (idempotency)
  if [ "$NEW_NAME" = "$name" ]; then
    echo "NOOP: $name" >> /tmp/normalize-log.txt
    continue
  fi

  # PUT new name
  cu_api PUT "task/$cu_id" "$(jq -n --arg n "$NEW_NAME" '{name:$n}')" > /dev/null

  # Add the type tag if not already present
  if ! echo "$tags" | grep -qiw "$TYPE_TAG"; then
    cu_api POST "task/$cu_id/tag/$TYPE_TAG" '{}' > /dev/null
  fi

  echo "RENAMED: $name → $NEW_NAME (tag +$TYPE_TAG)" >> /tmp/normalize-log.txt
  RENAMED=$((RENAMED+1))
  sleep 0.2
done < /tmp/bad-named.tsv

echo "=== Normalize Summary ===" >> /tmp/normalize-log.txt
echo "Scanned: $SCANNED | Renamed: $RENAMED" >> /tmp/normalize-log.txt
tail -3 /tmp/normalize-log.txt
```
