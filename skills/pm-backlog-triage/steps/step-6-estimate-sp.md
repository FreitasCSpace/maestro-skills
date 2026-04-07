# Step 6: Estimate Missing SP (with parent/subtask rollup) → /tmp/sp-log.txt

Two-pass strategy:
1. **Leaf pass** — for any task with no children that has SP=0, estimate via heuristic and PUT to ClickUp
2. **Rollup pass** — for any parent task with SP=0, sum SP of its immediate children and PUT to ClickUp

Parents are never estimated by heuristic — their SP is always the sum of their children.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/sp-log.txt

# Build parent set: any task ID that appears as `.parent` of another task
jq '[.[] | .parent | select(. != null)] | unique' /tmp/cu-backlog.json > /tmp/parent-ids.json

# Leaves: tasks NOT in parent set, with SP=0
jq --slurpfile parents /tmp/parent-ids.json '
  [ .[]
    | select((.id | IN($parents[0][]))| not)
    | select((.sp|tostring) == "0" or (.sp|tostring) == "" or .sp == null)
    | {id, name: .name[0:60], tags}
  ]
' /tmp/cu-backlog.json > /tmp/no-sp-leaves.json

LEAF_COUNT=$(jq length /tmp/no-sp-leaves.json)
PARENT_COUNT=$(jq length /tmp/parent-ids.json)
echo "Leaves needing SP: $LEAF_COUNT | Parents to roll up: $PARENT_COUNT" | tee /tmp/sp-log.txt

# ── Pass 1: Estimate leaves via heuristic ─────────────────────────────
LEAF_SET=0; MAX=50
for row in $(jq -r '.[] | @base64' /tmp/no-sp-leaves.json); do
  [ $LEAF_SET -ge $MAX ] && break
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  TAGS=$(echo "$row"|base64 -d|jq -r '.tags|join(",")')

  SP=2
  case "$TAGS" in
    *security*|*compliance*) SP=8;;
    *bug*)
      if echo "$NAME" | grep -qiE "critical|crash|data.loss"; then SP=8; else SP=5; fi;;
    *feature*|*enhancement*)
      if   echo "$NAME" | grep -qiE "refactor|rewrite|migrate|redesign"; then SP=21
      elif echo "$NAME" | grep -qiE "add|create|new|implement";          then SP=13
      else SP=5; fi;;
    *infra*|*ci*|*config*) SP=3;;
  esac

  cu_api POST "task/$ID/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null
  echo "LEAF SP: $NAME → ${SP}" >> /tmp/sp-log.txt
  LEAF_SET=$((LEAF_SET+1)); sleep 0.2
done

# ── Pass 2: Re-fetch backlog so parent rollup sees the new leaf SPs ───
# (We just modified custom fields; the cached cu-backlog.json is now stale for SP.
#  Cheap re-fetch: only first page is enough for rollup since subtasks live in same list.)
cu_api GET "list/$LIST_MASTER_BACKLOG/task?include_closed=false&subtasks=true&page=0" \
  | jq --arg cf "$SP_FIELD_ID" '
    [ .tasks[] | {
        id,
        name: .name[0:80],
        sp: (((.custom_fields[]? | select(.id==$cf) | .value) // 0) | tonumber),
        parent: (.parent // null)
    } ]' > /tmp/cu-rollup.json

# For each parent, compute sum of immediate children SP
jq '
  group_by(.parent)
  | map(select(.[0].parent != null) | {parent: .[0].parent, total_sp: ([.[].sp] | add // 0)})
' /tmp/cu-rollup.json > /tmp/parent-sums.json

# Find parents with SP=0 that have non-zero rollup totals
jq --slurpfile sums /tmp/parent-sums.json '
  [ .[]
    | . as $p
    | select(.sp == 0)
    | ($sums[0][] | select(.parent == $p.id)) as $rollup
    | select($rollup.total_sp > 0)
    | {id, name: .name[0:60], rollup_sp: $rollup.total_sp}
  ]
' /tmp/cu-rollup.json > /tmp/parents-needing-rollup.json

ROLLUP_COUNT=$(jq length /tmp/parents-needing-rollup.json)
echo "Parents to update with rollup SP: $ROLLUP_COUNT" >> /tmp/sp-log.txt

PARENT_SET=0
for row in $(jq -r '.[] | @base64' /tmp/parents-needing-rollup.json); do
  [ $PARENT_SET -ge $MAX ] && break
  ID=$(echo "$row"|base64 -d|jq -r '.id')
  NAME=$(echo "$row"|base64 -d|jq -r '.name')
  SP=$(echo "$row"|base64 -d|jq -r '.rollup_sp')

  cu_api POST "task/$ID/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null
  echo "ROLLUP SP: $NAME → ${SP} (sum of subtasks)" >> /tmp/sp-log.txt
  PARENT_SET=$((PARENT_SET+1)); sleep 0.2
done

echo "Leaves set: $LEAF_SET | Parents rolled up: $PARENT_SET" >> /tmp/sp-log.txt
tail -8 /tmp/sp-log.txt
```
