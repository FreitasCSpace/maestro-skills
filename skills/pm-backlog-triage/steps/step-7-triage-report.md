# Step 7: Build Triage Context → /tmp/triage-context.md

Computes raw backlog metrics and dumps structured data for the AI synthesis in Step 8.
This step is mechanical — Step 8 turns it into a manager-readable narrative.

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Reuse the paginated backlog cache from Step 2 (already has age + assignees + tags + parent)
jq '[.[] | {id, name, pri, assignees: (.assignees|join(",")), age, tags, sp: (.sp|tostring), parent}]' \
  /tmp/cu-backlog.json > /tmp/triage.json

TOTAL=$(jq length /tmp/triage.json)
BUGS=$(jq '[.[]|select(.tags|any(.=="bug"))]|length' /tmp/triage.json)
FEATS=$(jq '[.[]|select(.tags|any(.=="enhancement" or .=="feature"))]|length' /tmp/triage.json)
SECURITY=$(jq '[.[]|select(.tags|any(.=="security" or .=="compliance"))]|length' /tmp/triage.json)
URG=$(jq '[.[]|select(.pri=="1")]|length' /tmp/triage.json)
HIGH=$(jq '[.[]|select(.pri=="2")]|length' /tmp/triage.json)
NORM=$(jq '[.[]|select(.pri=="3")]|length' /tmp/triage.json)
LOW=$(jq '[.[]|select(.pri=="4")]|length' /tmp/triage.json)
UNASSIGNED=$(jq '[.[]|select(.assignees=="" and .age>7)]|length' /tmp/triage.json)
AGING=$(jq "[.[]|select(.age>$AGING_TASK_DAYS)]|length" /tmp/triage.json)
STALE=$(jq "[.[]|select(.age>$STALE_TASK_DAYS and .age<=$AGING_TASK_DAYS)]|length" /tmp/triage.json)
NO_SP=$(jq '[.[]|select(.sp=="0" or .sp=="" or .sp=="null")]|length' /tmp/triage.json)
ORPHANS=$(wc -l < /tmp/cu-orphans.tsv 2>/dev/null || echo 0)

# Domain breakdown
> /tmp/domain-stats.tsv
for d in backend frontend mobile ai-cv sdk infra bots video other; do
  COUNT=$(jq --arg d "$d" '[.[]|select(.tags|any(.==$d))]|length' /tmp/triage.json)
  [ "$COUNT" -gt 0 ] && printf '%s\t%s\n' "$d" "$COUNT" >> /tmp/domain-stats.tsv
done

# Action counts from this run
IMPORTED=$(grep -c "^IMPORT " /tmp/import-log.txt 2>/dev/null || echo 0)
DELETED_GHOSTS=$(grep -c "^DELETED " /tmp/stale-issues-log.txt 2>/dev/null || echo 0)
CLOSED_GH=$(grep -c "^CLOSED " /tmp/stale-issues-log.txt 2>/dev/null || echo 0)
SP_LEAVES=$(grep -c "^LEAF SP:" /tmp/sp-log.txt 2>/dev/null || echo 0)
SP_ROLLUPS=$(grep -c "^ROLLUP SP:" /tmp/sp-log.txt 2>/dev/null || echo 0)
LINKED_ORPHANS=$(grep -c "^LINKED:" /tmp/orphan-link-log.txt 2>/dev/null || echo 0)
COMMENT_OPS=$(grep -E "^(created|updated|deduped)" /tmp/comment-log.txt 2>/dev/null | wc -l)

# Build structured context for AI synthesis
cat > /tmp/triage-context.md << REOF
=== BACKLOG SNAPSHOT ===
total_tasks=$TOTAL
bugs=$BUGS features=$FEATS security_compliance=$SECURITY
priority urgent=$URG high=$HIGH normal=$NORM low=$LOW
unassigned_aging=$UNASSIGNED stale=$STALE aging=$AGING
no_sp=$NO_SP orphans_no_gh=$ORPHANS

=== DOMAIN BREAKDOWN ===
$(cat /tmp/domain-stats.tsv 2>/dev/null)

=== THIS RUN'S ACTIONS ===
imported_new=$IMPORTED
deleted_ghost_tasks=$DELETED_GHOSTS
closed_via_gh=$CLOSED_GH
sp_estimated_leaves=$SP_LEAVES
sp_rolled_up_parents=$SP_ROLLUPS
fuzzy_linked_orphans=$LINKED_ORPHANS
gh_bot_comments=$COMMENT_OPS

=== TOP UNASSIGNED AGING (>7d, no owner) ===
$(jq -r '.[]|select(.assignees=="" and .age>7)|"- (\(.age)d, pri \(.pri)) \(.name)"' /tmp/triage.json | head -8)

=== TOP AGING (>${AGING_TASK_DAYS}d) ===
$(jq -r ".[]|select(.age>$AGING_TASK_DAYS)|\"- (\\(.age)d, pri \\(.pri), \\(.assignees)) \\(.name)\"" /tmp/triage.json | head -8)

=== URGENT/HIGH PRIORITY OPEN ===
$(jq -r '.[]|select((.pri=="1" or .pri=="2") and .age>3)|"- (pri \(.pri), \(.age)d, \(.assignees)) \(.name)"' /tmp/triage.json | head -8)

=== ORPHAN LINKING RESULTS ===
$(tail -20 /tmp/orphan-link-log.txt 2>/dev/null)
REOF

cat /tmp/triage-context.md
```

## AI Synthesis — Backlog Health Briefing

**INSTRUCTION TO CLAUDE:** Read `/tmp/triage-context.md` and write a Slack-ready
manager briefing to `/tmp/triage-report.md` using the Write tool.

Use the same Manager Briefing format as pm-daily-pulse:
- Header line with totals + priority breakdown
- Flags section with action items
- Narrative paragraphs grouped by theme (bugs vs features, by domain, by urgency)
- Actions Taken summary at the end

### Output format (write exactly this structure):

```
# Backlog Health — {DATE}

📊 *{TOTAL} tasks total* — {BUGS} bugs · {FEATS} features · {SECURITY} security/compliance
🚨 Urgent={URG} | High={HIGH} | Normal={NORM} | Low={LOW}

━━━━━━━━━━━━━━━━━━━━━
⚠️  FLAGS BEFORE YOU READ

(Only include lines that apply — omit section entirely if nothing critical)
• [N] urgent/high-priority tasks aging more than 3 days
• [N] tasks unassigned for over a week — need owners
• [N] tasks still missing SP estimates
• [N] orphan tasks couldn't be auto-linked to GitHub — manual review
• [Domain] is the largest backlog ([N] tasks) — possible imbalance

━━━━━━━━━━━━━━━━━━━━━
📂  BACKLOG STATE

[1-2 paragraph narrative covering: which domains dominate, where the
priority pressure sits, what aging items look like, and any red flags
about the mix. Be specific — name actual stale tasks if there are any
critical ones. Don't list every task; just call out the worst offenders.]

━━━━━━━━━━━━━━━━━━━━━
🔧  THIS RUN'S WORK

[Bullet list summarizing what the bot actually did. Skip lines with 0:]
• Imported [N] new GitHub issues into ClickUp
• Auto-linked [N] orphan tasks to existing GH issues
• Estimated SP for [N] leaf tasks · rolled up [N] parent tasks
• Closed [N] CU tasks (GH issue closed) · deleted [N] ghosts (GH issue gone)
• Refreshed [N] GitHub bot comments

━━━━━━━━━━━━━━━━━━━━━
🎯  NEEDS ATTENTION

[Bulleted list of the top 3-5 specific tasks that most need a human:
unassigned-and-aging, urgent-and-stale, or orphan-link-failures.
Use real task names from the context file.]
```

**Rules:**
- Be specific with task names — pull from "TOP UNASSIGNED AGING" / "TOP AGING" / "URGENT/HIGH PRIORITY" sections
- Skip any subsection that has no items
- Keep narrative tight — 2 sentences max per paragraph
- Write the complete file to `/tmp/triage-report.md` using the Write tool
- After writing, run: `cat /tmp/triage-report.md`
