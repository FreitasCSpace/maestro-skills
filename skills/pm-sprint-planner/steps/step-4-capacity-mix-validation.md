# Step 4: Capacity + Mix Validation

Hard limit on SP and task count — posts Slack alert and stops if exceeded.
Mix warnings are soft — included in report and Slack but do not block.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
CAND_COUNT=$(jq 'length' /tmp/candidates.json)
TOTAL_SP=$(jq '[.[].sp] | add // 0' /tmp/candidates.json)

BUGS=$(jq       '[.[] | select(.tags | any(test("bug";"i")))]        | length' /tmp/candidates.json)
FEATURES=$(jq   '[.[] | select(.tags | any(test("feature|enhancement";"i")))] | length' /tmp/candidates.json)
COMPLIANCE=$(jq '[.[] | select(.tags | any(test("compliance|security";"i")))] | length' /tmp/candidates.json)

echo "Capacity: $CAND_COUNT tasks (max 25) | $TOTAL_SP SP (max $SPRINT_BUDGET_SP)"
echo "Mix: $BUGS bugs | $FEATURES features | $COMPLIANCE compliance | Target: $SPRINT_MIX"

if [ "$CAND_COUNT" -gt 25 ] || [ "$TOTAL_SP" -gt "$SPRINT_BUDGET_SP" ]; then
  OVER_MSG="⛔ *Sprint Planner Blocked — Over Capacity*
  Tasks: ${CAND_COUNT}/25 | SP: ${TOTAL_SP}/${SPRINT_BUDGET_SP}
  Remove candidates to get under limits, then run again."
  slack_post "$SLACK_SPRINT" "Sprint Planner Blocked: $SPRINT_NAME" "$OVER_MSG" "pm-sprint-planner"
  echo "BLOCKED: over capacity. Slack alert posted."
  touch /tmp/planner-skip; return 0
fi

> /tmp/mix-warnings.txt
[ "$FEATURES" -lt "$SPRINT_MIN_FEATURES" ] && \
  echo "⚠️ Only $FEATURES features (min $SPRINT_MIN_FEATURES) — consider adding more." >> /tmp/mix-warnings.txt
[ "$COMPLIANCE" -gt "$SPRINT_MAX_COMPLIANCE" ] && \
  echo "⚠️ $COMPLIANCE compliance tasks (max $SPRINT_MAX_COMPLIANCE) — consider deferring some." >> /tmp/mix-warnings.txt

echo "Under capacity — proceeding"

printf '%s\t%s\t%s\t%s\t%s\n' \
  "$CAND_COUNT" "$TOTAL_SP" "$BUGS" "$FEATURES" "$COMPLIANCE" \
  > /tmp/planner-metrics.tsv
```
