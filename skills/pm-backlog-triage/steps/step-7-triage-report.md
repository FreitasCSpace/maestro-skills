# Step 7: Triage Report → /tmp/triage-report.md

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Reuse the paginated backlog cache from Step 2 (already has age + assignees)
jq '[.[] | {name, pri, assignees: (.assignees|join(",")), age, tags}]' \
  /tmp/cu-backlog.json > /tmp/triage.json

TOTAL=$(jq length /tmp/triage.json)
BUGS=$(jq '[.[]|select(.tags|any(.=="bug"))]|length' /tmp/triage.json)
FEATS=$(jq '[.[]|select(.tags|any(.=="enhancement" or .=="feature"))]|length' /tmp/triage.json)
URG=$(jq '[.[]|select(.pri=="1")]|length' /tmp/triage.json)
HIGH=$(jq '[.[]|select(.pri=="2")]|length' /tmp/triage.json)
NORM=$(jq '[.[]|select(.pri=="3")]|length' /tmp/triage.json)
LOW=$(jq '[.[]|select(.pri=="4")]|length' /tmp/triage.json)
UNASSIGNED=$(jq '[.[]|select(.assignees=="" and .age>7)]|length' /tmp/triage.json)
AGING=$(jq "[.[]|select(.age>$AGING_TASK_DAYS)]|length" /tmp/triage.json)
STALE=$(jq "[.[]|select(.age>$STALE_TASK_DAYS and .age<=$AGING_TASK_DAYS)]|length" /tmp/triage.json)

cat > /tmp/triage-report.md << REOF
# Backlog Health — $(date +%Y-%m-%d)

## Summary
- **Total:** $TOTAL tasks | **Bugs:** $BUGS | **Features:** $FEATS
- **Priority:** Urgent=$URG High=$HIGH Normal=$NORM Low=$LOW

## Actions Taken
$(tail -3 /tmp/import-log.txt)
$(tail -1 /tmp/comment-log.txt)
$(tail -1 /tmp/sp-log.txt)
$(tail -1 /tmp/stale-issues-log.txt)
$(tail -1 /tmp/orphan-link-log.txt 2>/dev/null)

## Needs Attention
- Unassigned >7d: $UNASSIGNED
- Stale >${STALE_TASK_DAYS}d: $STALE
- Aging >${AGING_TASK_DAYS}d: $AGING
$(jq -r '.[]|select(.assignees=="" and .age>7)|"- UNASSIGNED (\(.age)d): \(.name)"' /tmp/triage.json | head -5)
$(jq -r ".[]|select(.age>$AGING_TASK_DAYS)|\"- AGING (\\(.age)d): \\(.name)\"" /tmp/triage.json | head -5)
REOF

cat /tmp/triage-report.md
```
