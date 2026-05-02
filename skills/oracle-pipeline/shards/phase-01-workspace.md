# Phase 01 — Workspace, BMAD Context, Stories Index

## Step 1.0 — Workspace

```bash
rm -rf /tmp/oracle-work 2>/dev/null
mkdir -p /tmp/oracle-work/workspace /tmp/oracle-work/stories
cd /tmp/oracle-work
```

## Step 1.1 — Clone backlog at the BMAD context branch

The BMAD context for each project lives on branch `bmad/<slug>-context`, not on main.

```bash
CONTEXT_BRANCH="bmad/${PROJECT_SLUG}-context"

gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- \
  --depth=1 --branch "$CONTEXT_BRANCH" 2>/dev/null || {
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context branch \`$CONTEXT_BRANCH\` not found — aborting"
  gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label oracle:implementing --add-label oracle:blocked-pipeline-failed
  exit 1
}

CTX_DIR="backlog/bmad-context/$PROJECT_SLUG"
[ -d "$CTX_DIR" ] || {
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Context dir \`bmad-context/$PROJECT_SLUG/\` not found on branch \`$CONTEXT_BRANCH\`"
  exit 1
}

for f in feature-intent.json stories-output.md; do
  [ -f "$CTX_DIR/$f" ] || {
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "Missing required BMAD file: \`$f\`"
    exit 1
  }
done

echo "BMAD context loaded from $CONTEXT_BRANCH"
```

## Step 1.2 — Extract involved repos (bash only, no Read tool)

```bash
INVOLVED_REPOS=($(jq -r '.involved_repos[].full_name | split("/")[1]' \
  "$CTX_DIR/feature-intent.json"))
echo "Involved repos: ${INVOLVED_REPOS[*]}"
[ ${#INVOLVED_REPOS[@]} -gt 0 ] || { echo "BLOCKED: no involved_repos in feature-intent.json"; exit 1; }
```

## Step 1.3 — Distill stories-output.md into a compact index

```bash
STORIES_RAW="$CTX_DIR/stories-output.md"
STORIES_IDX="/tmp/oracle-work/stories-index.md"

awk '
  /^## (Story|Epic)/ { print; next }
  /^### Story/       { print; next }
  /^\*\*(Story ID|title|affected_modules|new_files_needed|acceptance_criteria|dev_notes)\*\*/ { print; next }
  /^- /              { print; next }
' "$STORIES_RAW" > "$STORIES_IDX"

echo "Stories index: $(wc -l < "$STORIES_IDX") lines (from $(wc -l < "$STORIES_RAW") raw)"
```

Read `stories-index.md` with the Read tool. If > 300 lines, read in chunks of 300
using `offset` + `limit`. Extract from it:
- Ordered story list: Epic N → Story N.M titles
- Per-story: `affected_modules`, `acceptance_criteria`

---

**Next:** Read `shards/phase-02-repos.md`
