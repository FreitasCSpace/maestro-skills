# Phase 02 — Clone Repos, Branch, BMAD Workflows, PIPELINE.md

## Step 2.0 — Concurrency check

```bash
ACTIVE=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label oracle:implementing --state open --limit 100 \
  --json number | jq length)

if [ "$ACTIVE" -gt 2 ]; then
  echo "Concurrency cap reached — leaving label in place"; exit 0
fi
```

## Step 2.1 — Clone and configure repos

```bash
BRANCH="feat/oracle-project-$PROJECT_SLUG"

for REPO in "${INVOLVED_REPOS[@]}"; do
  gh repo clone "$TARGET_ORG/$REPO" "workspace/$REPO" -- --depth=50
  cd "workspace/$REPO"
  git fetch --unshallow 2>/dev/null || true
  git config user.email "oracle-pipeline@carespace.ai"
  git config user.name "Oracle Pipeline"
  git remote set-url origin \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_ORG}/${REPO}.git"

  # Create or reset project branch
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git checkout -B "$BRANCH" origin/main
  else
    git checkout -B "$BRANCH" origin/main
  fi
  cd /tmp/oracle-work
done
```

## Step 2.2 — Locate BMAD workflow files

```bash
find_workflow() {
  local name="$1"
  find "$HOME/.claude/skills" "$HOME/bmad-method-src/src" \
    -path "*/${name}/workflow.md" 2>/dev/null | head -1
}

WF_CREATE_STORY=$(find_workflow "bmad-create-story")
WF_DEV_STORY=$(find_workflow "bmad-dev-story")
WF_CODE_REVIEW=$(find_workflow "bmad-code-review")

echo "create-story: $WF_CREATE_STORY"
echo "dev-story:    $WF_DEV_STORY"
echo "code-review:  $WF_CODE_REVIEW"

[ -f "$WF_CREATE_STORY" ] || { echo "BLOCKED: bmad-create-story workflow not found"; exit 1; }
[ -f "$WF_DEV_STORY" ]    || { echo "BLOCKED: bmad-dev-story workflow not found"; exit 1; }
[ -f "$WF_CODE_REVIEW" ]  || { echo "BLOCKED: bmad-code-review workflow not found"; exit 1; }
```

## Step 2.3 — Write PIPELINE.md

```bash
cat > /tmp/oracle-work/PIPELINE.md <<EOF
# Oracle Project Pipeline Run

## Project
slug: $PROJECT_SLUG
anchor-issue: $TARGET_ORG/the-oracle-backlog#$ANCHOR
involved repos: ${INVOLVED_REPOS[*]}

## Status
IN_PROGRESS

## Story Log
EOF
```

---

**Next:** Read `shards/phase-03-story-loop.md`
