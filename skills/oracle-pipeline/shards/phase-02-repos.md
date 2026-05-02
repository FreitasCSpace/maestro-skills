# Phase 02 — Clone Repos, Install BMAD, Branch, PIPELINE.md

## Step 2.0 — Concurrency check

```bash
ACTIVE=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label maestro:implementing --state open --limit 100 \
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

## Step 2.2 — Clone BMAD workflow repo

Workflows live in `FreitasCSpace/carespace-bmad-workflow` under
`bmad-template/bmm/workflows/4-implementation/`.

```bash
gh repo clone FreitasCSpace/carespace-bmad-workflow /tmp/oracle-work/bmad-workflows -- \
  --depth=1 --filter=blob:none --sparse 2>/dev/null || \
gh repo clone FreitasCSpace/carespace-bmad-workflow /tmp/oracle-work/bmad-workflows -- \
  --depth=1

# Sparse checkout only the implementation workflows
cd /tmp/oracle-work/bmad-workflows
git sparse-checkout set bmad-template/bmm/workflows/4-implementation 2>/dev/null || true
cd /tmp/oracle-work

BMAD_WF_BASE="/tmp/oracle-work/bmad-workflows/bmad-template/bmm/workflows/4-implementation"

WF_CREATE_STORY="$BMAD_WF_BASE/bmad-create-story/workflow.md"
WF_DEV_STORY="$BMAD_WF_BASE/bmad-dev-story/workflow.md"
WF_CODE_REVIEW="$BMAD_WF_BASE/bmad-code-review/workflow.md"

echo "create-story : $WF_CREATE_STORY"
echo "dev-story    : $WF_DEV_STORY"
echo "code-review  : $WF_CODE_REVIEW"

[ -f "$WF_CREATE_STORY" ] || { echo "BLOCKED: bmad-create-story workflow not found"; exit 1; }
[ -f "$WF_DEV_STORY" ]    || { echo "BLOCKED: bmad-dev-story workflow not found"; exit 1; }
[ -f "$WF_CODE_REVIEW" ]  || { echo "BLOCKED: bmad-code-review workflow not found"; exit 1; }
```

## Step 2.3 — Install BMAD into each repo

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"

  if [ ! -f "_bmad/bmm/config.yaml" ]; then
    echo "Installing BMAD in $REPO..."
    npx bmad-method install \
      --non-interactive \
      --ide claude-code \
      --modules bmm 2>&1 | tail -5

    [ -f "_bmad/bmm/config.yaml" ] || {
      echo "BMAD install failed in $REPO — continuing without"
      cd /tmp/oracle-work
      continue
    }

    grep -q "^_bmad/" .gitignore 2>/dev/null || echo "_bmad/" >> .gitignore
  else
    echo "BMAD already installed in $REPO"
  fi

  cd /tmp/oracle-work
done
```

## Step 2.4 — Write PIPELINE.md

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
