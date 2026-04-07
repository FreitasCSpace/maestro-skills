# Step 3: Calculate Metrics → /tmp/retro-context.md

Health and completion based on **SP delivered**, not task count.
Carryover safety check runs here — if exceeded, posts Slack alert and sets skip sentinel.
Dumps structured context for AI synthesis in Step 5.

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

# Carryover safety check
if [ "$CARRY" -gt 15 ]; then
  MSG="⚠️ *Retro blocked for $SPRINT_NAME* — $CARRY carryovers exceeds limit (15). Manual review required before moving tasks."
  slack_post "$SLACK_SPRINT" "Retro Blocked: $SPRINT_NAME" "$MSG" "pm-retrospective"
  echo "BLOCKED: $CARRY carryovers > 15. Slack alert posted. Stopping."
  touch /tmp/retro-skip; return 0
fi

# Per-assignee breakdown
jq -r '
  group_by(.assignees[0] // "unassigned")
  | map({
      assignee: (.[0].assignees[0] // "unassigned"),
      done:    [.[]|select(.status|test("complete|done|closed|resolved"))]|length,
      carried: [.[]|select(.status|test("complete|done|closed|resolved")|not)]|length,
      done_sp: ([.[]|select(.status|test("complete|done|closed|resolved"))|.sp]|add // 0),
      total_sp: ([.[].sp]|add // 0)
    })
  | .[] | "\(.assignee)\t\(.done)\t\(.carried)\t\(.done_sp)\t\(.total_sp)"
' /tmp/retro-tasks.json > /tmp/retro-by-assignee.tsv

# Build structured context for AI synthesis
cat > /tmp/retro-context.md << REOF
=== SPRINT SNAPSHOT ===
sprint=$SPRINT_NAME
health=$HEALTH ($EMOJI)
completion_pct=$COMPLETION
tasks_done=$DONE/$TOTAL
sp_delivered=$DONE_SP/$TOTAL_SP (budget: $SPRINT_BUDGET_SP)
carryovers=$CARRY

=== PER ASSIGNEE (assignee TAB done TAB carried TAB done_sp TAB total_sp) ===
$(cat /tmp/retro-by-assignee.tsv)

=== COMPLETED TASKS ===
$(jq -r '.[] | select(.status | test("complete|done|closed|resolved"))
              | "[DONE] \(.name) — \(.assignees|join(",")) [\(.sp)SP]"' \
  /tmp/retro-tasks.json)

=== CARRYOVERS ===
$(jq -r '.[] | select(.status | test("complete|done|closed|resolved") | not)
              | "[CARRY] \(.name) — \(.assignees|join(",")) [\(.sp)SP, pri \(.pri)]"' \
  /tmp/retro-tasks.json)
REOF

cat /tmp/retro-context.md
```

## AI Synthesis — Retro Briefing

**INSTRUCTION TO CLAUDE:** Read `/tmp/retro-context.md` and write the retro digest
to `/tmp/retro-report.md` using the Write tool.

### Output format:

```
# Sprint Retro: {SPRINT_NAME}

{H_EMOJI} *{HEALTH}* — {COMPLETION}% complete ({DONE_SP}/{TOTAL_SP} SP)
✅ {DONE}/{TOTAL} tasks done | 🔁 {CARRY} carried over | 🎯 Velocity: {DONE_SP} SP

━━━━━━━━━━━━━━━━━━━━━
🏆  WHAT SHIPPED

[1-2 sentence narrative paragraph summarizing the biggest wins this sprint.
Group thematically — call out major features delivered, not every ticket.
Mention top contributors by name with their done count and SP delivered.]

━━━━━━━━━━━━━━━━━━━━━
🔁  CARRYING OVER ({CARRY} items)

[Narrative paragraph: which workstreams slipped, why it matters, and what
priorities will be bumped going into next sprint. Be specific — name the
2-3 biggest carryover items. Skip section if CARRY is 0.]

━━━━━━━━━━━━━━━━━━━━━
👥  CONTRIBUTORS

[For each assignee in /tmp/retro-by-assignee.tsv (skip "unassigned"),
one line: "*Name* — Done X/Y · {sp_done}/{sp_total} SP"
Sort by SP delivered descending. Skip people with 0 SP.]

━━━━━━━━━━━━━━━━━━━━━
🎓  TAKEAWAYS

[2-3 bullet points based on the data: completion rate, carryover patterns,
imbalances. Forward-looking. Examples:
• High carryover concentrated in [domain] — split scope next sprint
• Velocity dropped from typical X SP to Y — investigate why
• [Person] consistently overcommitted — adjust capacity]
```

**Rules:**
- Be specific with names and ticket titles from the context
- Skip sections with no content
- Tone: factual, forward-looking, no blame
- Write the complete file to `/tmp/retro-report.md` using the Write tool
- After writing, run: `cat /tmp/retro-report.md`
```
