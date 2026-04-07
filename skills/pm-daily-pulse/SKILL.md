---
name: pm-daily-pulse
description: Daily sprint standup digest — fetches sprint tasks from ClickUp, groups by assignee, checks stale/blocked, posts standup-ready digest to Slack. Idempotent — updates existing message.
---

# PM Daily Pulse

**Fully autonomous. Read-only on ClickUp. File-based pipeline — all data in /tmp files.**

## GUARDRAILS
- ⛔ SLACK: ONLY post to channels from context.sh ($SLACK_ENGINEERING, $SLACK_STANDUP, $SLACK_SPRINT, etc). If channel not found, FAIL — NEVER substitute another channel. NEVER post to #carespace-team, #general, #eng-general.
- Read-only on ClickUp — NEVER creates, updates, or deletes tasks
- Idempotent Slack posts — updates existing digest if already posted today
- No sprint → write /tmp/no-sprint sentinel and skip remaining steps (do NOT exit)
- **ALL API responses go to /tmp files. Only read summaries into context.**

## STEP 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | SP field: $SP_FIELD_ID"
rm -f /tmp/no-sprint   # clear sentinel from prior run
```

---

## EXECUTION

### Step 1: Find Active Sprint → /tmp/sprint-info.json

Active sprint = a list in FOLDER_SPRINTS whose `start_date <= now < due_date`.
Falls back to the most recently started non-done list if no exact date match.

```bash
source ~/.claude/skills/_pm-shared/context.sh
NOW_MS=$(( $(date +%s) * 1000 ))

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq --argjson now "$NOW_MS" '
      [ .lists[]
        | select(.status.status != "done")
        | select(
            (.start_date // "0" | tonumber) <= $now
            and ((.due_date // "9999999999999" | tonumber) > $now)
          )
      ]
      | sort_by(.start_date // "0" | tonumber)
      | last
      // (
          # fallback: latest-started non-done list
          [ .lists[] | select(.status.status != "done") ]
          | sort_by(.start_date // "0" | tonumber)
          | last
        )
      | {id, name, status: .status.status,
         start_ms: (.start_date // "0" | tonumber),
         due_ms:   (.due_date   // "0" | tonumber)}
    ' \
  > /tmp/sprint-info.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-info.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-info.json)

if [ -z "$SPRINT_ID" ]; then
  echo "NO ACTIVE SPRINT — skipping digest"
  touch /tmp/no-sprint
  slack_post "$SLACK_STANDUP" "Daily Pulse — $(date +%Y-%m-%d)" \
    "No active sprint found. Digest skipped." "pm-daily-pulse"
else
  echo "Sprint: $SPRINT_NAME (id: $SPRINT_ID)"
fi
```

### Step 2: Fetch Sprint Tasks → /tmp/sprint-tasks.json

Paginated. SP stored as number. Uses `date_updated` (not comments) for staleness.

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_ID=$(jq -r '.id' /tmp/sprint-info.json)

> /tmp/sprint-pages.ndjson
PAGE=0; MAX_PAGES=10
while [ $PAGE -lt $MAX_PAGES ]; do
  cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true&page=$PAGE" \
    > /tmp/sprint-page.json
  COUNT=$(jq '.tasks | length' /tmp/sprint-page.json)
  [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ] && break
  cat /tmp/sprint-page.json >> /tmp/sprint-pages.ndjson
  echo >> /tmp/sprint-pages.ndjson
  PAGE=$((PAGE+1))
  [ "$COUNT" -lt 100 ] && break
  sleep 0.3
done

jq -s --arg cf "$SP_FIELD_ID" '
  [ .[].tasks[] | {
      id,
      name: .name[0:70],
      desc: ((.description // "") | gsub("<[^>]+>"; "") | .[0:300]),
      status: (.status.status | ascii_downcase),
      assignees: [.assignees[].username],
      pri: (.priority.priority // "4"),
      sp:  ((.custom_fields[]? | select(.id==$cf) | .value // "0") // "0" | tonumber),
      updated_ms: (.date_updated // "0" | tonumber),
      url
    }
  ]' /tmp/sprint-pages.ndjson > /tmp/sprint-tasks.json

echo "Sprint tasks: $(jq length /tmp/sprint-tasks.json)"
[ "$(jq length /tmp/sprint-tasks.json)" = "0" ] && \
  echo "WARNING: sprint exists but has 0 tasks — check ClickUp configuration"
```

### Step 3: Stale Check + Open PRs

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

### Step 4: Build Manager Briefing Digest → /tmp/sprint-health.md

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
DONE=$(jq   '[.[]|select(.status|test("complete|done|closed|resolved"))]|length'     /tmp/sprint-tasks.json)
IN_P=$(jq   '[.[]|select(.status|test("in progress|review|in review|active"))]|length' /tmp/sprint-tasks.json)
BLKD=$(jq   '[.[]|select(.status|test("blocked|waiting"))]|length'                   /tmp/sprint-tasks.json)
TODO=$(jq   '[.[]|select(.status|test("to do|open|pending|backlog|new"))]|length'    /tmp/sprint-tasks.json)
TOTAL_SP=$(jq '[.[].sp]|add//0'                                                       /tmp/sprint-tasks.json)
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

  P_DONE=$(echo  "$PERSON_TASKS" | jq '[.[]|select(.status|test("complete|done|closed|resolved"))]|length')
  P_INP=$(echo   "$PERSON_TASKS" | jq '[.[]|select(.status|test("in progress|review|in review|active"))]|length')
  P_BLKD=$(echo  "$PERSON_TASKS" | jq '[.[]|select(.status|test("blocked|waiting"))]|length')
  P_TODO=$(echo  "$PERSON_TASKS" | jq '[.[]|select(.status|test("to do|open|pending|backlog|new"))]|length')
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

# ── INSTRUCTION TO CLAUDE: Generate the Manager Briefing ────────────
#
# Read /tmp/person-context.md (raw task data per person).
# Read /tmp/stale-tasks.tsv (format: days<TAB>name<TAB>assignees).
#
# Produce /tmp/sprint-health.md with EXACTLY this structure:
#
# ------- FORMAT START -------
#
# # Sprint Digest — {DATE}
#
# {H_EMOJI} *{HEALTH}* — {SPRINT_NAME}
# ✅ {DONE}/{TOTAL} done ({DONE_SP}/{TOTAL_SP} SP) | 🔄 {IN_P} in progress | 🚫 {BLKD} blocked | ⏳ {DAYS_LEFT}d left ({DUE_FMT}) | Sprint {TIME_PCT}% elapsed
#
# ━━━━━━━━━━━━━━━━━━━━━
# ⚠️  FLAGS BEFORE YOU READ
#
# (Only include lines that apply — skip section entirely if nothing to flag)
# • [person] has [N] tasks in progress with 0 SP — estimates needed
# • [person]'s task "[name]" has been stale for [N] days — check in
# • [N] tasks are unassigned — need an owner
# • [person] has [N] blocked items
#
# ━━━━━━━━━━━━━━━━━━━━━
# 👥  TEAM STATUS
#
# (For each person in /tmp/assignees.txt, one section:)
#
# *[Firstname Lastname]* — {status_emoji} {status_label} ({P_SP_DONE}/{P_SP_TOTAL} SP)
# [1-2 sentence narrative paragraph. Third person, present tense. Focus on
#  what problem they are solving, not just ticket names. Use task names AND
#  descriptions from person-context.md. Be specific. Mention blocked items
#  or stale items if they apply to this person. If they have completions,
#  mention them in the same paragraph or as a brief closing sentence.]
#
# Status emoji + label rules:
#   - ✅ Nearly done   → sp_done >= 80% of sp_total OR done >= 80% of tasks
#   - 🔄 Active        → has in-progress tasks, no blockers
#   - ⚠️ Needs attention → has blocked tasks OR zero-sp active tasks OR stale items
#   - 📋 Not started   → all tasks are todo, nothing in progress or done
#
# ━━━━━━━━━━━━━━━━━━━━━
# 🔗  OPEN PRs  (only if PR_COUNT > 0)
# • [repo#num] — [title] @[author]
# (max 5 lines, from /tmp/open-prs.txt which has format: repo#num<TAB>title<TAB>@author)
#
# ------- FORMAT END -------
#
# RULES:
# - Do NOT include a raw task list anywhere. Only narrative + flags.
# - Use display names (capitalize first letter) not raw usernames where possible.
# - Keep each person's paragraph to 2-3 sentences max.
# - If a person has 0 active or done tasks (all todo), use 📋 Not started and one brief sentence.
# - The flags section should be sharp and actionable. Skip if no flags apply.
# - Completions are woven into the narrative, NOT listed separately as tasks.
# - Write the full file to /tmp/sprint-health.md using the Write tool.
#
# Available variables for substitution (already computed above):
#   DATE=$(date +"%B %d, %Y")
#   H_EMOJI, HEALTH, SPRINT_NAME, DONE, TOTAL, DONE_SP, TOTAL_SP
#   IN_P, BLKD, TODO, DAYS_LEFT, DUE_FMT, TIME_PCT, UNASSIGNED

cat /tmp/sprint-health.md
```

### Step 5: Post to Slack (idempotent)

```bash
source ~/.claude/skills/_pm-shared/context.sh
[ -f /tmp/no-sprint ] && echo "No sprint — skip" && return 0

SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
BODY=$(tail -n +3 /tmp/sprint-health.md)   # skip markdown title line
slack_post "$SLACK_STANDUP" "Daily Pulse — $SPRINT_NAME — $(date +%Y-%m-%d)" "$BODY" "pm-daily-pulse"
```
