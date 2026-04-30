# Phase 03 — Concurrency, Clone, Branch, Install, PIPELINE.md

## Step 0.6 — Acquire concurrency slot

A project is "active" if any of its user-stories carry `oracle:implementing`.
Cap is 2 concurrent active projects.

```bash
ACTIVE=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label oracle:implementing --state open --limit 1000 \
  --json labels \
  | jq '[.[] | .labels[] | select(.name | startswith("project:")) | .name] | unique | length')

if [ "$ACTIVE" -ge 2 ]; then
  echo "Concurrency cap reached ($ACTIVE active); leaving maestro-ready in place"
  exit 0
fi

# Do NOT bulk-change all story labels here.
# Labels transition one story at a time as each story is picked up in Phase 1.
# (maestro-ready → oracle:implementing at story start; oracle:implementing →
#  oracle:story-done at story end)

gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Oracle pipeline started for \`$PROJECT_LABEL\` ($STORY_COUNT user-stories). Tracking on this issue."
```

## Step 0.7 — Clone every involved repo

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  gh repo clone "$TARGET_ORG/$REPO" "workspace/$REPO" -- --depth=50
  cd "workspace/$REPO"
  git fetch --unshallow 2>/dev/null || true
  git config user.email "oracle-pipeline@carespace.ai"
  git config user.name "Oracle Pipeline"
  git remote set-url origin \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_ORG}/${REPO}.git"
  cd /tmp/oracle-work
done
```

## Step 0.8 — Create or reset project branch (idempotent)

```bash
BRANCH="feat/oracle-project-$PROJECT_SLUG"

for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  git fetch origin main "$BRANCH" 2>/dev/null || git fetch origin main

  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    NON_AI=$(git log "origin/main..origin/$BRANCH" \
      --pretty='%ae' | grep -v '^oracle-pipeline@carespace\.ai$' | head -1)
    if [ -n "$NON_AI" ]; then
      gh issue comment "$ANCHOR_ISSUE" \
        --repo "$TARGET_ORG/the-oracle-backlog" \
        --body "Human commits on AI project branch in \`$REPO\` — manual reconciliation required"
      exit 1
    fi
    git checkout -B "$BRANCH" origin/main
  else
    git checkout -B "$BRANCH" origin/main
  fi
  cd /tmp/oracle-work
done
```

## Step 0.9 — Auto-detect stack and install

For each cloned repo, detect in priority order:
`package-lock.json` → `yarn.lock` → `bun.lock` → `package.json` →
`build.gradle*` → `go.mod` → `requirements.txt` → `pyproject.toml` →
`pubspec.yaml` → `Gemfile`.

Generate a temporary `CLAUDE.md` per repo if missing (same template as
`pipeline/`). Do NOT commit a generated `CLAUDE.md` on the project branch.

## Step 0.10 — Write PIPELINE.md

Write to `/tmp/oracle-work/PIPELINE.md`:

```markdown
# Oracle Project Pipeline Run

## Project
slug: <project-slug>
label: <project:X>
anchor-issue: <org>/the-oracle-backlog#<N>
group user-stories: <list of issue numbers>
involved repos: <list>
total stories (BMAD): <N>

## BMAD Context
- feature-intent.json: <key fields summary>
- stories-output.md: <epic/story counts>

## Status
IN_PROGRESS

## Story Log
(filled per story below)
```

PIPELINE.md is your run-memory. It is NOT committed to any repo.

---

**Next:** Read `shards/phase-04-bootstrap.md`
