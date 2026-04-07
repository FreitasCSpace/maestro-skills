# Step 0: Load Shared Context

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Sprint folder: $FOLDER_SPRINTS | Candidates: $LIST_SPRINT_CANDIDATES | Budget: $SPRINT_BUDGET_SP SP"
rm -f /tmp/planner-skip   # clear sentinel from prior run
```
