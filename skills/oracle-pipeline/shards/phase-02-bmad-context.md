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

**Read ONE file only: `stories-output.md`.**

Use the Read tool on `backlog/bmad-context/$PROJECT_SLUG/stories-output.md`.
This is the ONLY BMAD file that goes into context. Extract from it:
- Dependency-ordered story list (Epic 1: 1.1, 1.2, …; Epic 2: 2.1, 2.2, …)
- Per-story `affected_modules`, `new_files_needed`, `dev_notes`,
  `acceptance_criteria`

**DO NOT read architecture.md, prd.md, front-end-spec.md, feature-intent.json,
or any other file with the Read tool.** If a specific story needs a section
from one of those files, read only that section at that moment — not now.

Match GitHub user-story issues from 0.3 to BMAD stories by title or by
`story:N.M` label. If neither matches: log a warning to PIPELINE.md and use
BMAD ordering.

## Step 0.5b — Read CARESPACE_CONTEXT scoped to involved_repos

```bash
CTX=~/.claude/skills/oracle-pipeline/CARESPACE_CONTEXT.md
SCOPED=/tmp/oracle-work/context-scoped.md

# Always include the prologue (everything before the first per-repo section)
awk '/^## carespace-/{exit} {print}' "$CTX" > "$SCOPED"

# Append only the sections for repos this project touches
for REPO in "${INVOLVED_REPOS[@]}"; do
  awk -v r="## $REPO" '
    $0 ~ "^"r" " || $0 == r {p=1}
    p && /^## carespace-/ && $0 !~ "^"r" " && $0 != r {p=0}
    p {print}
  ' "$CTX" >> "$SCOPED"
done

wc -c "$SCOPED"  # expect ~5–10KB not 47KB
```

Then read `context-scoped.md` ONCE via the Read tool. Use it to:
1. Match each repo to its Repository Map row (stack, default branch, build cmds).
2. Use per-repo "Where to look by issue type" tables to jump to relevant dirs.
3. Check HIPAA notes before touching PHI files (Profile, Client, Evaluation,
   Survey, Auth, Storage).

**Do NOT read the full `CARESPACE_CONTEXT.md`.** Never re-read the scoped
extract after this step.

If `wc -c` < 1000 bytes, awk match failed — fall back to reading the full
file via the Read tool (recovery path only, not default).

---

**Next:** Read `shards/phase-03-repos.md`
