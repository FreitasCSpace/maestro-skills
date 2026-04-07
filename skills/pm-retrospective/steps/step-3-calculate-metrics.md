# Step 3: Calculate Metrics → /tmp/retro-report.md

Health and completion based on **SP delivered**, not task count.
Carryover safety check runs here — if exceeded, posts Slack alert and sets skip sentinel.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/retro-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/retro-sprint.json)
SPRINT_ID=$(jq -r '.id' /tmp/retro-sprint.json)

TOTAL=$(jq 'length' /tmp/retro-tasks.json)
DONE=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))]|length'  /tmp/retro-tasks.json)
CARRY=$(jq '[.[]|select(.status|test("complete|done|closed|resolved")|not)]|length' /tmp/retro-tasks.json)

TOTAL_SP=$(jq '[.[].sp]       | add // 0' /tmp/retro-tasks.json)
DONE_SP=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))|.sp] | add // 0' /tmp/retro-tasks.json)

[ "$TOTAL_SP" -gt 0 ] && COMPLETION=$(( DONE_SP * 100 / TOTAL_SP )) || COMPLETION=0

if   [ "$COMPLETION" -ge 80 ]; then HEALTH="Healthy";  EMOJI="🟢"
elif [ "$COMPLETION" -ge 60 ]; then HEALTH="At Risk";  EMOJI="🟡"
else                                 HEALTH="Underrun"; EMOJI="🔴"; fi

# Carryover safety check — alert + stop before touching anything
if [ "$CARRY" -gt 15 ]; then
  MSG="⚠️ *Retro blocked for $SPRINT_NAME* — $CARRY carryovers exceeds limit (15). Manual review required before moving tasks."
  slack_post "$SLACK_SPRINT" "Retro Blocked: $SPRINT_NAME" "$MSG" "pm-retrospective"
  echo "BLOCKED: $CARRY carryovers > 15. Slack alert posted. Stopping."
  touch /tmp/retro-skip; return 0
fi

DONE_LIST=$(jq -r '
  .[] | select(.status | test("complete|done|closed|resolved"))
      | "• *\(.name)* — _\(.assignees|join(", "))_ `\(.sp)SP`"
' /tmp/retro-tasks.json | head -20)

CARRY_LIST=$(jq -r '
  .[] | select(.status | test("complete|done|closed|resolved") | not)
      | "• *\(.name)* — _\(.assignees|join(", "))_ `\(.sp)SP` [pri \(.pri)]"
' /tmp/retro-tasks.json | head -20)

{
  printf '# Sprint Retro: %s\n\n' "$SPRINT_NAME"
  printf '## %s %s — %d%% complete (%d/%d SP)\n' "$EMOJI" "$HEALTH" "$COMPLETION" "$DONE_SP" "$TOTAL_SP"
  printf '- **Tasks:** %d/%d done | **Carryovers:** %d\n' "$DONE" "$TOTAL" "$CARRY"
  printf '- **Velocity:** %d SP delivered (budget: %d SP)\n\n' "$DONE_SP" "$SPRINT_BUDGET_SP"
  printf '## Done\n%s\n\n' "${DONE_LIST:-_None — odd sprint!_}"
  printf '## Carried Over\n%s\n' "${CARRY_LIST:-_None — perfect sprint!_}"
} > /tmp/retro-report.md

cat /tmp/retro-report.md
```
