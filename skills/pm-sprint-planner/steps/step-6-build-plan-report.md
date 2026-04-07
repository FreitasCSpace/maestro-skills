# Step 6: Build Plan Report + Post to Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-state.json)
DUE_FMT=$(date -d "@$(( DUE_MS / 1000 ))" +%Y-%m-%d 2>/dev/null || echo "TBD")

IFS=$'\t' read -r CAND_COUNT TOTAL_SP BUGS FEATURES COMPLIANCE < /tmp/planner-metrics.tsv

MIX_WARNINGS=$(cat /tmp/mix-warnings.txt 2>/dev/null)

TASK_LIST=$(jq -r '
  .[] | "• *\(.name)* — _\(.assignees|join(", "))_ `\(.sp)SP` [pri \(.pri)]"
' /tmp/candidates.json | head -25)

{
  printf '# Sprint Plan: %s\n\n' "$SPRINT_NAME"
  printf '## Summary\n'
  printf -- '- **Tasks:** %s | **Total SP:** %s / %s | **Due:** %s\n' \
    "$CAND_COUNT" "$TOTAL_SP" "$SPRINT_BUDGET_SP" "$DUE_FMT"
  printf -- '- **Mix:** %s bugs + %s features + %s compliance\n' \
    "$BUGS" "$FEATURES" "$COMPLIANCE"
  printf -- '- **Target mix:** %s\n' "$SPRINT_MIX"
  [ -n "$MIX_WARNINGS" ] && printf '\n## Warnings\n%s\n' "$MIX_WARNINGS"
  printf '\n## Tasks (by priority)\n%s\n' "$TASK_LIST"
} > /tmp/sprint-plan.md

cat /tmp/sprint-plan.md

BODY=$(tail -n +3 /tmp/sprint-plan.md)
slack_post "$SLACK_SPRINT" "Sprint Plan: $SPRINT_NAME" "$BODY" "pm-sprint-planner"
```
