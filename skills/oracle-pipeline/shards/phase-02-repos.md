# Phase 02 — Clone Repos, Install BMAD, Branch, PIPELINE.md

## Step 2.0 — Concurrency check

```bash
ACTIVE=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label oracle:implementing --state open --limit 100 \
  --json number | jq length)

if [ "$ACTIVE" -gt 2 ]; then
  echo "Concurrency cap reached ($ACTIVE active) — leaving label in place"; exit 0
fi
```

## Step 2.1 — Clone and configure target repos

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

  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git checkout -B "$BRANCH" origin/main
  else
    git checkout -B "$BRANCH" origin/main
  fi
  cd /tmp/oracle-work
done
```

## Step 2.2 — Install BMAD into each repo

BMAD workflows run as `claude --print` subprocesses rooted at the repo dir.
They need `_bmad/` present to locate config and persona files.

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"

  if [ ! -f "_bmad/bmm/config.yaml" ]; then
    echo "Installing BMAD in $REPO..."
    npx bmad-method install \
      --non-interactive \
      --ide claude-code \
      --modules bmm 2>&1 | tail -5

    # Verify
    [ -f "_bmad/bmm/config.yaml" ] || {
      echo "BMAD install failed in $REPO — trying interactive fallback"
      # Non-interactive failed; install to a shared location instead
      cd /tmp/oracle-work
      continue
    }

    # Don't commit the BMAD install — add to .gitignore
    grep -q "^_bmad/" .gitignore 2>/dev/null || echo "_bmad/" >> .gitignore
  else
    echo "BMAD already installed in $REPO"
  fi

  cd /tmp/oracle-work
done
```

## Step 2.3 — Locate BMAD workflow files

Search in installed locations and the BMAD source clone:

```bash
find_workflow() {
  local name="$1"
  # Check each repo's install, then global skills, then source clone
  for REPO in "${INVOLVED_REPOS[@]}"; do
    local p="workspace/$REPO/.claude/skills/${name}/workflow.md"
    [ -f "$p" ] && { echo "/tmp/oracle-work/$p"; return; }
  done
  find "$HOME/.claude/skills" "$HOME/bmad-method-src/src" \
    -path "*/${name}/workflow.md" 2>/dev/null | head -1
}

WF_CREATE_STORY=$(find_workflow "bmad-create-story")
WF_DEV_STORY=$(find_workflow "bmad-dev-story")
WF_CODE_REVIEW=$(find_workflow "bmad-code-review")

echo "create-story : $WF_CREATE_STORY"
echo "dev-story    : $WF_DEV_STORY"
echo "code-review  : $WF_CODE_REVIEW"

[ -f "$WF_CREATE_STORY" ] || { echo "BLOCKED: bmad-create-story not found"; exit 1; }
[ -f "$WF_DEV_STORY" ]    || { echo "BLOCKED: bmad-dev-story not found"; exit 1; }
[ -f "$WF_CODE_REVIEW" ]  || { echo "BLOCKED: bmad-code-review not found"; exit 1; }
```

## Step 2.4 — Write PIPELINE.md

```bash
cat > /tmp/oracle-work/PIPELINE.md <<EOF
# Oracle Project Pipeline Run

## Project
slug: $PROJECT_SLUG
anchor-issue: $TARGET_ORG/the-oracle-backlog#$ANCHOR
context-branch: bmad/${PROJECT_SLUG}-context
involved repos: ${INVOLVED_REPOS[*]}

## Status
IN_PROGRESS

## Story Log
EOF
```

---

**Next:** Read `shards/phase-03-story-loop.md`
