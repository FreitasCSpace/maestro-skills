# Step 6: Build Plan Context + AI Synthesis → /tmp/sprint-plan.md

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/planner-skip ] && echo "Skipping (sentinel set)" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-state.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-state.json)
DUE_FMT=$(date -d "@$(( DUE_MS / 1000 ))" +%Y-%m-%d 2>/dev/null || echo "TBD")

IFS=$'\t' read -r CAND_COUNT TOTAL_SP BUGS FEATURES COMPLIANCE < /tmp/planner-metrics.tsv
MIX_WARNINGS=$(cat /tmp/mix-warnings.txt 2>/dev/null)

# Per-assignee load
jq -r '
  group_by(.assignees[0] // "unassigned")
  | map({
      assignee: (.[0].assignees[0] // "unassigned"),
      count: length,
      sp: ([.[].sp]|add // 0)
    })
  | sort_by(-.sp)
  | .[] | "\(.assignee)\t\(.count)\t\(.sp)"
' /tmp/candidates.json > /tmp/planner-by-assignee.tsv

# Build context for AI synthesis
cat > /tmp/planner-context.md << REOF
=== SPRINT PLAN SNAPSHOT ===
sprint=$SPRINT_NAME
due=$DUE_FMT
total_tasks=$CAND_COUNT
total_sp=$TOTAL_SP/$SPRINT_BUDGET_SP
bugs=$BUGS features=$FEATURES compliance=$COMPLIANCE
target_mix=$SPRINT_MIX

=== MIX WARNINGS ===
${MIX_WARNINGS:-(none)}

=== PER ASSIGNEE LOAD (assignee TAB tasks TAB sp) ===
$(cat /tmp/planner-by-assignee.tsv)

=== ALL CANDIDATES (sorted by priority then SP) ===
$(jq -r '.[] | "[pri \(.pri), \(.sp)SP, \(.assignees|join(","))] \(.name)"' /tmp/candidates.json)
REOF

cat /tmp/planner-context.md
```

## AI Synthesis — Sprint Plan Briefing

**INSTRUCTION TO CLAUDE:** Read `/tmp/planner-context.md` and write the sprint plan
digest to `/tmp/sprint-plan.md` using the Write tool.

### Output format:

```
# Sprint Plan: {SPRINT_NAME}

🎯 *{TOTAL_SP}/{BUDGET} SP* across {CAND_COUNT} tasks · Due {DUE_FMT}
🐛 {BUGS} bugs · ✨ {FEATURES} features · 🔒 {COMPLIANCE} compliance

━━━━━━━━━━━━━━━━━━━━━
⚠️  MIX WARNINGS

(Skip section if no warnings)
[copy mix-warnings lines verbatim]

━━━━━━━━━━━━━━━━━━━━━
🎯  SPRINT THEME

[1-2 sentence narrative paragraph: what's the dominant theme this sprint
based on the candidate mix? Frontend-heavy? Bug-cleanup? Feature push?
Compliance work? Read the task names and call out the actual workstream(s).]

━━━━━━━━━━━━━━━━━━━━━
👥  TEAM LOAD

[For each assignee in /tmp/planner-by-assignee.tsv (sorted by SP desc):
*Name* — N tasks · {sp} SP
Skip "unassigned" unless count > 0 (then flag it).]

━━━━━━━━━━━━━━━━━━━━━
📋  TOP PRIORITIES

[Top 5-8 candidates sorted by priority then SP. Format:
• `[pri 1, 8SP]` Task name — @assignee
Pull from "ALL CANDIDATES" — focus on pri 1 and 2.]

━━━━━━━━━━━━━━━━━━━━━
✅  READY TO START

Sprint is finalized. {CAND_COUNT} tasks moved into the sprint list.
```

**Rules:**
- Be specific with task names from context
- Skip sections with no content
- Sprint theme should reflect actual work, not boilerplate
- Write the complete file to `/tmp/sprint-plan.md` using the Write tool
- After writing, run: `cat /tmp/sprint-plan.md` then post via slack_post

```bash
BODY=$(tail -n +3 /tmp/sprint-plan.md)
slack_post "$SLACK_SPRINT" "Sprint Plan: $SPRINT_NAME" "$BODY" "pm-sprint-planner"
```
