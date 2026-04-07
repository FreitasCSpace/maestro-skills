# Step 2: Identify Stale/Unupdated Tasks Per User → /tmp/sync-stale-by-user.json

Skip users who already have an in-progress task — they're actively working.
Uses `updated_ms` (from `date_updated`) for staleness, not comment timestamps.

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW_MS=$(( $(date +%s) * 1000 ))
STALE_MS=$(( STALE_TASK_DAYS * 86400 * 1000 ))

# Users with at least one in-progress task → skip them
jq -r '[.[] | select(.status | test("in progress|review|active")) | .assignees[]] | unique | .[]' \
  /tmp/sync-tasks.json > /tmp/sync-active-users.txt
echo "Users with active tasks (will skip): $(wc -l < /tmp/sync-active-users.txt)"

# Group stale tasks by assignee, exclude active users
jq --argjson now "$NOW_MS" --argjson stale "$STALE_MS" \
  --rawfile skip /tmp/sync-active-users.txt '
  def active_users: ($skip | split("\n") | map(select(. != "")));
  [
    .[]
    | select(.status | test("complete|done|closed|resolved") | not)
    | select(($now - .updated_ms) > $stale)
    | select(.assignees | length > 0)
  ]
  | group_by(.assignees[0])
  | map({
      assignee: .[0].assignees[0],
      tasks: [.[] | {
        id, name, status, sp, url,
        days_stale: ((($now - .updated_ms) / 86400000) | floor)
      }]
    })
  | [.[] | select(.assignee as $a | active_users | index($a) | not)]
' /tmp/sync-tasks.json > /tmp/sync-stale-by-user.json

echo "Users with stale tasks: $(jq length /tmp/sync-stale-by-user.json)"
jq -r '.[] | "\(.assignee): \(.tasks | length) stale tasks"' /tmp/sync-stale-by-user.json
```
