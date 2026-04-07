# Step 4: Build Manager Briefing Digest → /tmp/sprint-health.md

**Option B — Manager Briefing format.**
Flags first (items needing attention), then per-person AI narrative paragraphs,
then completions. Designed to be read by a non-technical manager in 60 seconds.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
DUE_MS=$(jq -r '.due_ms' /tmp/sprint-info.json)
START_MS=$(jq -r '.start_ms' /tmp/sprint-info.json)
NOW_MS=$(( $(date +%s) * 1000 ))
NOW_S=$(date +%s)

# ── Sprint health math ───────────────────────────────────────────────
TOTAL=$(jq 'length' /tmp/sprint-tasks.json)
DONE=$(jq   '[.[]|select(.status|test("complete|done|closed|resolved"))]|length'        /tmp/sprint-tasks.json)
IN_P=$(jq   '[.[]|select(.status|test("in progress|review|in review|active"))]|length' /tmp/sprint-tasks.json)
BLKD=$(jq   '[.[]|select(.status|test("blocked|waiting"))]|length'                     /tmp/sprint-tasks.json)
TODO=$(jq   '[.[]|select(.status|test("to do|open|pending|backlog|new"))]|length'      /tmp/sprint-tasks.json)
TOTAL_SP=$(jq '[.[].sp]|add//0'                                                         /tmp/sprint-tasks.json)
DONE_SP=$(jq  '[.[]|select(.status|test("complete|done|closed|resolved"))|.sp]|add//0' /tmp/sprint-tasks.json)

[ "$TOTAL_SP" -gt 0 ] && COMPLETION=$(( DONE_SP * 100 / TOTAL_SP )) || COMPLETION=0

# Time progress
START_S=$(( START_MS / 1000 ))
DUE_S=$(( DUE_MS / 1000 ))
DURATION_S=$(( DUE_S - START_S ))
if [ "$DURATION_S" -gt 0 ]; then
  ELAPSED_S=$(( NOW_S - START_S ))
  TIME_PCT=$(( ELAPSED_S * 100 / DURATION_S ))
  [ "$TIME_PCT" -lt 0 ] && TIME_PCT=0
  [ "$TIME_PCT" -gt 100 ] && TIME_PCT=100
  DAYS_LEFT=$(( (DUE_S - NOW_S) / 86400 ))
  [ "$DAYS_LEFT" -lt 0 ] && DAYS_LEFT=0
  DUE_FMT=$(date -d "@$DUE_S" +%b\ %d 2>/dev/null || echo "?")
else
  TIME_PCT=50; DAYS_LEFT="?"; DUE_FMT="no due date"
fi

# Health indicator
THRESHOLD=$(( TIME_PCT - 10 ))
[ "$THRESHOLD" -lt 0 ] && THRESHOLD=0
if   [ "$COMPLETION" -ge "$THRESHOLD" ];           then HEALTH="On Track"; H_EMOJI="🟢"
elif [ "$COMPLETION" -ge $(( THRESHOLD - 15 )) ];  then HEALTH="At Risk";  H_EMOJI="🟡"
else HEALTH="Behind"; H_EMOJI="🔴"; fi

STALE_COUNT=$(wc -l < /tmp/stale-tasks.tsv)
PR_COUNT=$(wc -l < /tmp/open-prs.txt)
UNASSIGNED=$(jq '[.[]|select(.assignees|length==0)]|length' /tmp/sprint-tasks.json)

# ── Extract unique assignees (non-unassigned, sorted) ───────────────
jq -r '
  [.[] | select(.assignees|length>0) | .assignees[]] | unique | .[]
' /tmp/sprint-tasks.json > /tmp/assignees.txt

# ── Per-person metrics + raw task context for AI ────────────────────
# Produces /tmp/person-context.md — structured input for Claude synthesis
> /tmp/person-context.md

while IFS= read -r person; do
  PERSON_TASKS=$(jq --arg p "$person" '[.[]|select(.assignees|contains([$p]))]' /tmp/sprint-tasks.json)

  P_DONE=$(echo   "$PERSON_TASKS" | jq '[.[]|select(.status|test("complete|done|closed|resolved"))]|length')
  P_INP=$(echo    "$PERSON_TASKS" | jq '[.[]|select(.status|test("in progress|review|in review|active"))]|length')
  P_BLKD=$(echo   "$PERSON_TASKS" | jq '[.[]|select(.status|test("blocked|waiting"))]|length')
  P_TODO=$(echo   "$PERSON_TASKS" | jq '[.[]|select(.status|test("to do|open|pending|backlog|new"))]|length')
  P_SP_DONE=$(echo  "$PERSON_TASKS" | jq '[.[]|select(.status|test("complete|done|closed|resolved"))|.sp]|add//0')
  P_SP_TOTAL=$(echo "$PERSON_TASKS" | jq '[.[].sp]|add//0')
  P_ZERO_SP=$(echo  "$PERSON_TASKS" | jq '[.[]|select(.sp==0)]|length')

  printf '=== PERSON: %s | done=%s in_progress=%s blocked=%s todo=%s sp=%s/%s zero_sp=%s ===\n' \
    "$person" "$P_DONE" "$P_INP" "$P_BLKD" "$P_TODO" "$P_SP_DONE" "$P_SP_TOTAL" "$P_ZERO_SP" \
    >> /tmp/person-context.md

  # Active tasks (in progress + blocked) — full name + desc for AI
  echo "$PERSON_TASKS" | jq -r '
    .[] | select(.status | test("in progress|review|in review|active|blocked|waiting"))
        | "[ACTIVE|\(.status)] \(.name)\(if .desc != "" then " — \(.desc)" else "" end)"
  ' >> /tmp/person-context.md

  # Completed tasks — names only
  echo "$PERSON_TASKS" | jq -r '
    .[] | select(.status | test("complete|done|closed|resolved"))
        | "[DONE] \(.name)"
  ' >> /tmp/person-context.md

  # Todo tasks — names only
  echo "$PERSON_TASKS" | jq -r '
    .[] | select(.status | test("to do|open|pending|backlog|new"))
        | "[TODO] \(.name)"
  ' >> /tmp/person-context.md

  echo "" >> /tmp/person-context.md

done < /tmp/assignees.txt
```

## AI Synthesis — Manager Briefing

**INSTRUCTION TO CLAUDE:** Read `/tmp/person-context.md` (raw task data per person) and
`/tmp/stale-tasks.tsv` (format: `days<TAB>name<TAB>assignees`), then write the final
digest to `/tmp/sprint-health.md` using the Write tool.

Use these already-computed values in the output:
- `DATE` = today's date (e.g. "April 7, 2026")
- `H_EMOJI`, `HEALTH`, `SPRINT_NAME`
- `DONE`, `TOTAL`, `DONE_SP`, `TOTAL_SP`, `IN_P`, `BLKD`, `TODO`
- `DAYS_LEFT`, `DUE_FMT`, `TIME_PCT`, `UNASSIGNED`

### Output format (write exactly this structure):

```
# Sprint Digest — {DATE}

{H_EMOJI} *{HEALTH}* — {SPRINT_NAME}
✅ {DONE}/{TOTAL} done ({DONE_SP}/{TOTAL_SP} SP) | 🔄 {IN_P} in progress | 🚫 {BLKD} blocked | ⏳ {DAYS_LEFT}d left ({DUE_FMT}) | Sprint {TIME_PCT}% elapsed

━━━━━━━━━━━━━━━━━━━━━
⚠️  FLAGS BEFORE YOU READ

• [Only include lines that apply — omit this section entirely if nothing to flag]
• [person] has [N] active tasks with 0 SP — estimates needed
• [person]'s task "[name]" stale for [N] days — needs check-in
• [N] tasks are unassigned — need an owner
• [person] has [N] blocked items

━━━━━━━━━━━━━━━━━━━━━
👥  TEAM STATUS

*[Display Name]* — {emoji} {label} ({P_SP_DONE}/{P_SP_TOTAL} SP)
[1-2 sentence narrative. Third person, present tense. What problem are they
solving? Mention blockers or stale items if applicable. Weave in completions.]

[repeat for each person in /tmp/assignees.txt]

━━━━━━━━━━━━━━━━━━━━━
🔗  OPEN PRs
• [repo#num] — [title] @[author]
[max 5 — omit section if PR_COUNT is 0]
```

**Status emoji + label rules:**
- ✅ Nearly done → SP done ≥ 80% of total, or done tasks ≥ 80%
- 🔄 Active → has in-progress tasks, no blockers
- ⚠️ Needs attention → has blocked tasks, zero-SP active tasks, or stale items
- 📋 Not started → everything todo, nothing in progress or done

**Rules:**
- No raw task lists anywhere — narrative only
- Capitalize display names (first letter of each word)
- Keep each paragraph to 2-3 sentences max
- Flags section: sharp and actionable — skip entirely if nothing to flag
- Write the complete file to `/tmp/sprint-health.md` using the Write tool
- After writing, run: `cat /tmp/sprint-health.md`
