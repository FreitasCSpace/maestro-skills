# Phase 01 — Workspace, BMAD Context, Stories Index

## Step 1.0 — Workspace

```bash
rm -rf /tmp/oracle-work 2>/dev/null
mkdir -p /tmp/oracle-work/workspace /tmp/oracle-work/stories
cd /tmp/oracle-work
```

## Step 1.1 — Clone backlog and validate

```bash
gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- --depth=1

CTX_DIR="backlog/bmad-context/$PROJECT_SLUG"
[ -d "$CTX_DIR" ] || {
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context not found at \`bmad-context/$PROJECT_SLUG/\` — aborting"
  gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label oracle:implementing --add-label oracle:blocked-pipeline-failed
  exit 1
}

for f in feature-intent.json stories-output.md; do
  [ -f "$CTX_DIR/$f" ] || {
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "Missing required BMAD file: \`$f\`"
    exit 1
  }
done
```

## Step 1.2 — Extract involved repos (bash only, no Read tool)

```bash
INVOLVED_REPOS=($(jq -r '.involved_repos[].full_name | split("/")[1]' \
  "$CTX_DIR/feature-intent.json"))
echo "Involved repos: ${INVOLVED_REPOS[*]}"
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

wc -l "$STORIES_IDX"
```

Read `stories-index.md` with the Read tool (use offset+limit of 300 lines if > 300 lines).
Extract:
- Ordered story list: Epic N → Story N.M titles
- Per-story: `affected_modules`, `acceptance_criteria`

## Step 1.4 — Update anchor issue body with full story list

```bash
STORY_LIST=$(grep -E "^### Story|^## Epic" "$STORIES_IDX" | sed 's/^/- /')

gh issue edit "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "$(printf '# %s\n\nAll epics and stories for this project:\n\n%s' \
    "$PROJECT_NAME" "$STORY_LIST")"
```

---

**Next:** Read `shards/phase-02-repos.md`
