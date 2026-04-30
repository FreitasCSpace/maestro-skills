# Phase 02 — BMAD Context Load + Scoped CareSpace Context

## Step 0.5 — Clone backlog and validate BMAD context

```bash
cd /tmp/oracle-work
gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- --depth=1
CTX_DIR="backlog/bmad-context/$PROJECT_SLUG"

cd "$CTX_DIR" 2>/dev/null || {
  gh issue comment "$ANCHOR_ISSUE" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context dir not found at \`bmad-context/$PROJECT_SLUG/\` — pipeline cannot run"
  exit 1
}

REQUIRED=(feature-intent.json stories-output.md)
MISSING=()
for f in "${REQUIRED[@]}"; do [ -f "$f" ] || MISSING+=("$f"); done

if [ ${#MISSING[@]} -gt 0 ]; then
  gh issue comment "$ANCHOR_ISSUE" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context incomplete: missing ${MISSING[*]}"
  jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
    gh issue edit "$n" --repo "$TARGET_ORG/the-oracle-backlog" --remove-label maestro-ready
  done
  exit 1
fi
cd /tmp/oracle-work
```

Extract `involved_repos` via bash — no Read tool needed for feature-intent.json:

```bash
INVOLVED_REPOS=($(jq -r '.involved_repos[].full_name | split("/")[1]' \
  backlog/bmad-context/$PROJECT_SLUG/feature-intent.json))
echo "Involved repos: ${INVOLVED_REPOS[*]}"
```

## Step 0.5a — Distill stories-output.md into a compact index

`stories-output.md` can be hundreds of lines. Do NOT read it raw — distill it
first with bash, then read only the compact output.

```bash
STORIES_RAW="backlog/bmad-context/$PROJECT_SLUG/stories-output.md"
STORIES_IDX="/tmp/oracle-work/stories-index.md"

# Extract only story headings + key fields (affected_modules, new_files_needed,
# acceptance_criteria, dev_notes). Strip all other prose.
awk '
  /^## (Story|Epic)/ { print; next }
  /^### Story/       { print; next }
  /^\*\*(affected_modules|new_files_needed|acceptance_criteria|dev_notes|Story ID|title)\*\*/ { print; next }
  /^- /              { if (in_key) print; next }
  /^$/               { in_key=0; next }
' "$STORIES_RAW" > "$STORIES_IDX"

wc -l "$STORIES_IDX"
```

Read `/tmp/oracle-work/stories-index.md` with the Read tool (it will be small).
Extract from it:
- Dependency-ordered story list (Epic 1: 1.1, 1.2, …; Epic 2: 2.1, 2.2, …)
- Per-story `affected_modules`, `new_files_needed`, `acceptance_criteria`

If the index is still > 400 lines, read it in chunks of 300 using `offset` and
`limit` parameters on the Read tool — do NOT try to read it all at once.

**DO NOT read architecture.md, prd.md, front-end-spec.md, feature-intent.json,
or the raw stories-output.md with the Read tool.** If a specific story needs
a section from those files, read only that section at that moment — not now.

Match GitHub user-story issues from 0.3 to BMAD stories by title. If no match:
log a warning to PIPELINE.md and use BMAD ordering.

## Step 0.5b — Scoped CareSpace context (tables only)

Build the scoped extract, then strip it down to tables and headings only —
narrative prose is not needed at this stage.

```bash
CTX=~/.claude/skills/oracle-pipeline/CARESPACE_CONTEXT.md
SCOPED=/tmp/oracle-work/context-scoped.md

# Prologue (before first per-repo section)
awk '/^## carespace-/{exit} {print}' "$CTX" > "$SCOPED"

# Per-repo sections for involved repos only
for REPO in "${INVOLVED_REPOS[@]}"; do
  awk -v r="## $REPO" '
    $0 ~ "^"r"( |$)" {p=1}
    p && /^## carespace-/ && $0 !~ "^"r"( |$)" {p=0}
    p {print}
  ' "$CTX" >> "$SCOPED"
done

# Strip prose — keep only headings, table rows, and code blocks
awk '
  /^#/       { print; next }
  /^\|/      { print; next }
  /^```/     { in_code=!in_code; print; next }
  in_code    { print; next }
' "$SCOPED" > /tmp/oracle-work/context-tables.md

wc -c /tmp/oracle-work/context-tables.md
```

Read `/tmp/oracle-work/context-tables.md` with the Read tool. Use it to:
1. Match each repo to its Repository Map row (stack, default branch, build cmds).
2. Use per-repo "Where to look by issue type" tables to navigate the codebase.
3. Note any HIPAA-flagged paths before touching PHI files.

If `context-tables.md` is still > 25 000 tokens, read it in two halves using
`offset` and `limit`. Do NOT skip this step — it is required before cloning.

**Never read the full `CARESPACE_CONTEXT.md`.** Never re-read these files after
this step.

---

**Next:** Read `shards/phase-03-repos.md`
