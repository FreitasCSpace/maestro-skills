# Phase 01 — Workspace, Story List, Anchor Issue

## Step 0.2 — Wipe and prepare workspace

```bash
rm -rf /tmp/oracle-work 2>/dev/null
mkdir -p /tmp/oracle-work /tmp/oracle-work/workspace
cd /tmp/oracle-work
```

**Work in `/tmp/oracle-work` for the entire run.** Never cd elsewhere without
returning here.

## Step 0.3 — List the project's user-story issues

```bash
gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label "$PROJECT_LABEL" --label maestro-ready --label user-story \
  --state open --limit 1000 \
  --json number,title,labels,body \
  > /tmp/oracle-work/stories.json

STORY_COUNT=$(jq length /tmp/oracle-work/stories.json)
[ "$STORY_COUNT" -gt 0 ] || {
  echo "BLOCKED: no user-story issues with $PROJECT_LABEL + maestro-ready"
  exit 1
}
```

These issues are the **trigger surface** only. The implementation contract is
in `bmad-context/<slug>/`.

## Step 0.4 — Resolve anchor issue

```bash
ANCHOR_ISSUE=$(jq -r '[.[] | .number] | min' /tmp/oracle-work/stories.json)
```

If the orchestrator provided `anchor_issue_number`, use that — but verify it
appears in `stories.json`. If not, exit 1.

---

**Next:** Read `shards/phase-02-bmad-context.md`
