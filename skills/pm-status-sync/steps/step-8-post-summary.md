# Step 8: Build Sync Context + AI Synthesis → /tmp/sync-summary.md → Slack

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sync-sprint.json)

UPDATES=$(jq  '[.[] | select(.type=="status_update")] | length' /tmp/sync-actions.json)
NEW_TASKS=$(jq '[.[] | select(.type=="new_task")]     | length' /tmp/sync-actions.json)
PINGED=$(jq  length /tmp/sync-pings-sent.json)
REPLIED=$(jq length /tmp/sync-replies.json)
NO_REPLY=$(( PINGED - REPLIED ))

# Status transition counts
DONE_COUNT=$(jq '[.[]|select(.type=="status_update" and .new_status=="closed")]|length' /tmp/sync-actions.json)
INPROG_COUNT=$(jq '[.[]|select(.type=="status_update" and .new_status=="in progress")]|length' /tmp/sync-actions.json)
BLOCKED_COUNT=$(jq '[.[]|select(.type=="status_update" and .new_status=="blocked")]|length' /tmp/sync-actions.json)
REVIEW_COUNT=$(jq '[.[]|select(.type=="status_update" and .new_status=="review")]|length' /tmp/sync-actions.json)

# Build context for AI synthesis
cat > /tmp/sync-context.md << REOF
=== SYNC SNAPSHOT ===
sprint=$SPRINT_NAME
pinged=$PINGED replied=$REPLIED no_reply=$NO_REPLY
status_updates=$UPDATES new_tasks=$NEW_TASKS

=== STATUS TRANSITIONS ===
moved_to_done=$DONE_COUNT
moved_to_in_progress=$INPROG_COUNT
moved_to_blocked=$BLOCKED_COUNT
moved_to_review=$REVIEW_COUNT

=== ALL UPDATES ===
$(jq -r '.[] | select(.type=="status_update") |
  "[\(.assignee)] \(.task_name): \(.old_status) → \(.new_status)\(if .comment != "" then " — \(.comment)" else "" end)"
' /tmp/sync-actions.json)

=== NEW TASKS REPORTED ===
$(jq -r '.[] | select(.type=="new_task") |
  "[\(.assignee)] \(.task_name) — \(.description)"
' /tmp/sync-actions.json)

=== BLOCKED ITEMS (need attention) ===
$(jq -r '.[] | select(.type=="status_update" and .new_status=="blocked") |
  "[\(.assignee)] \(.task_name)\(if .comment != "" then " — \(.comment)" else "" end)"
' /tmp/sync-actions.json)
REOF

cat /tmp/sync-context.md
```

## AI Synthesis — Snoop Sync Briefing

**INSTRUCTION TO CLAUDE:** Read `/tmp/sync-context.md` and write the sync summary
to `/tmp/sync-summary.md` using the Write tool. Maintain Snoop Dogg's voice
in the header/footer but keep the body factual and scannable.

### Output format:

```
🐕 *Snoop Sync Complete — {SPRINT_NAME}* 🎵

📤 Pinged: {PINGED} | 💬 Replied: {REPLIED} | 🔥 Updates: {UPDATES} | 🆕 New: {NEW_TASKS}

━━━━━━━━━━━━━━━━━━━━━
🚫  BLOCKED ITEMS — NEED EYES

(Skip section if no blocked items)
• [@assignee] Task name — comment if any

━━━━━━━━━━━━━━━━━━━━━
✅  WHAT MOVED

[1-2 sentence narrative: who closed the most, what theme of work
got pushed forward this morning. Group by person if it tells a story.
Examples: "Kishorkumar closed 3 iOS bug fixes. Andre moved his
Calendar Program work into review."]

━━━━━━━━━━━━━━━━━━━━━
🔄  STATUS BREAKDOWN

(Skip lines with 0)
• ✅ {DONE_COUNT} moved to done
• 🔄 {INPROG_COUNT} moved to in progress
• 👀 {REVIEW_COUNT} moved to review
• 🚫 {BLOCKED_COUNT} moved to blocked

━━━━━━━━━━━━━━━━━━━━━
🆕  NEW JOINTS LOGGED

(Skip section if no new tasks)
• [@assignee] Task name — short description

━━━━━━━━━━━━━━━━━━━━━
😶  NO REPLY YET ({NO_REPLY})

(Skip if 0)
[Pull from non-responders if available, otherwise just the count]

_Keep it real and update yo tasks, cuz! — Snoop D-O-double-G 🐕💨_
```

**Rules:**
- Blocked items section is FIRST — these are the ones that need eyes
- Skip any section with 0 items
- Use real names from the context
- Snoop voice only in header/footer; body stays factual
- Write the complete file to `/tmp/sync-summary.md` using the Write tool
- Then post:

```bash
BODY=$(cat /tmp/sync-summary.md)
slack_post "$SLACK_STANDUP" "🐕 Snoop Sync — $SPRINT_NAME" "$BODY" "pm-status-sync"
```
