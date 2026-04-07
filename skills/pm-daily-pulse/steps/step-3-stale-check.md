# Step 3: Stale Check + Open PRs

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

NOW_MS=$(( $(date +%s) * 1000 ))
STALE_MS=$(( STALE_TASK_DAYS * 86400 * 1000 ))

# Stale = not done/closed, and date_updated older than STALE_TASK_DAYS
jq -r --argjson now "$NOW_MS" --argjson stale "$STALE_MS" '
  .[] | select(.status | test("complete|done|closed|resolved") | not)
      | select(($now - .updated_ms) > $stale)
      | { name, assignees, updated_ms,
          days: ((($now - .updated_ms) / 86400000) | floor) }
      | "\(.days)d\t\(.name[0:60])\t\(.assignees|join(","))"
' /tmp/sprint-tasks.json > /tmp/stale-tasks.tsv 2>/dev/null

echo "Stale tasks: $(wc -l < /tmp/stale-tasks.tsv)"

# Open PRs across CI repos
> /tmp/open-prs.txt
for repo in $CI_REPOS; do
  gh pr list --repo "$GITHUB_ORG/$repo" --state open \
    --json number,title,author --limit 20 2>/dev/null \
    | jq -r --arg r "$repo" \
        '.[] | "\($r)#\(.number)\t\(.title[0:55])\t@\(.author.login)"' \
    >> /tmp/open-prs.txt
done
echo "Open PRs: $(wc -l < /tmp/open-prs.txt)"
```
