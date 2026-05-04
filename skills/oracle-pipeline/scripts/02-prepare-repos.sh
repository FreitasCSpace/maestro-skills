#!/usr/bin/env bash
# Phase 02 — Clone repos, install BMAD, code-graph index, write PIPELINE.md.
#
# Reads env.00.sh + env.01.sh.
# Writes: workspace/, BRANCH var, COMPLETED_STORIES list, env.02.sh, PIPELINE.md
set -euo pipefail

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
: "${TARGET_ORG:?}" "${ANCHOR:?}" "${PROJECT_SLUG:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
cd /tmp/oracle-work

# Tool preflight (Serena + code-graph required for large-codebase nav)
command -v serena         >/dev/null 2>&1 || { echo "BLOCKED: serena not found — rebuild Docker image"; exit 1; }
command -v code-graph-mcp >/dev/null 2>&1 || { echo "BLOCKED: code-graph-mcp not found"; exit 1; }

# Concurrency cap (max 2 active pipelines)
ACTIVE=$(gh issue list --repo "$TARGET_ORG/the-oracle-backlog" \
  --label maestro:implementing --state open --limit 100 --json number | jq length)
if [ "$ACTIVE" -gt 2 ]; then
  echo "Concurrency cap reached ($ACTIVE active) — leaving label in place"; exit 0
fi

BRANCH="feat/oracle-project-$PROJECT_SLUG"
COMPLETED_STORIES=()

for REPO in "${INVOLVED_REPOS[@]}"; do
  gh repo clone "$TARGET_ORG/$REPO" "workspace/$REPO" -- --depth=50
  cd "workspace/$REPO"
  git fetch --unshallow 2>/dev/null || true
  git config user.email "oracle-pipeline@carespace.ai"
  git config user.name "Oracle Pipeline"
  git remote set-url origin \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_ORG}/${REPO}.git"

  DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
  DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"
  echo "Default branch for $REPO: $DEFAULT_BRANCH"

  git fetch origin "$BRANCH" 2>/dev/null || true
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git checkout -B "$BRANCH" "origin/$BRANCH"
    echo "Branch $BRANCH exists in $REPO — resuming"
    DONE=$(git log "origin/${DEFAULT_BRANCH}..$BRANCH" --format="%s" 2>/dev/null \
      | grep -oE '\[Story [A-Za-z0-9._-]+\]' | sed 's/\[Story //;s/\]//' || true)
    for sk in $DONE; do
      [[ " ${COMPLETED_STORIES[*]} " =~ " $sk " ]] || COMPLETED_STORIES+=("$sk")
    done
  else
    git checkout -B "$BRANCH" "origin/${DEFAULT_BRANCH}"
    echo "Created new branch $BRANCH in $REPO"
  fi
  cd /tmp/oracle-work
done

if [ ${#COMPLETED_STORIES[@]} -gt 0 ]; then
  echo "Already committed: ${COMPLETED_STORIES[*]}"
fi

# Clone BMAD workflows (sparse)
gh repo clone FreitasCSpace/carespace-bmad-workflow /tmp/oracle-work/bmad-workflows -- \
  --depth=1 --filter=blob:none --sparse 2>/dev/null \
  || gh repo clone FreitasCSpace/carespace-bmad-workflow /tmp/oracle-work/bmad-workflows -- --depth=1
( cd /tmp/oracle-work/bmad-workflows \
  && git sparse-checkout set bmad-template/bmm/workflows/4-implementation 2>/dev/null || true )

BMAD_WF_BASE="/tmp/oracle-work/bmad-workflows/bmad-template/bmm/workflows/4-implementation"
WF_CREATE_STORY="$BMAD_WF_BASE/bmad-create-story/workflow.md"
WF_DEV_STORY="$BMAD_WF_BASE/bmad-dev-story/workflow.md"
WF_CODE_REVIEW="$BMAD_WF_BASE/bmad-code-review/workflow.md"
for f in "$WF_CREATE_STORY" "$WF_DEV_STORY" "$WF_CODE_REVIEW"; do
  [ -f "$f" ] || { echo "BLOCKED: BMAD workflow missing: $f"; exit 1; }
done

# Install BMAD into each repo + write per-repo .mcp.json + index code-graph
MCP_TPL="$SKILL_DIR/templates/mcp-config.json.template"
for REPO in "${INVOLVED_REPOS[@]}"; do
  REPO_ROOT="/tmp/oracle-work/workspace/$REPO"
  cd "$REPO_ROOT"

  if [ ! -f "_bmad/bmm/config.yaml" ]; then
    echo "Installing BMAD in $REPO..."
    npx bmad-method install --yes --ide claude-code --modules bmm 2>&1 | tail -5 || true
    if [ -f "_bmad/bmm/config.yaml" ]; then
      grep -q "^_bmad/" .gitignore 2>/dev/null || echo "_bmad/" >> .gitignore
    else
      echo "BMAD install failed in $REPO — continuing without"
    fi
  else
    echo "BMAD already installed in $REPO"
  fi

  sed "s|__REPO_ROOT__|$REPO_ROOT|g" "$MCP_TPL" > "$REPO_ROOT/.mcp.json"
  timeout 300 code-graph-mcp incremental-index 2>&1 | tail -3 \
    || echo "WARN: code-graph index skipped for $REPO"
  cd /tmp/oracle-work
done

# PIPELINE.md from template
sed -e "s|__SLUG__|$PROJECT_SLUG|g" \
    -e "s|__ANCHOR__|$TARGET_ORG/the-oracle-backlog#$ANCHOR|g" \
    -e "s|__REPOS__|${INVOLVED_REPOS[*]}|g" \
    "$SKILL_DIR/templates/pipeline-md.template" \
    > /tmp/oracle-work/PIPELINE.md

cat > /tmp/oracle-work/env.02.sh <<EOF
export BRANCH=$(printf %q "$BRANCH")
export WF_CREATE_STORY=$(printf %q "$WF_CREATE_STORY")
export WF_DEV_STORY=$(printf %q "$WF_DEV_STORY")
export WF_CODE_REVIEW=$(printf %q "$WF_CODE_REVIEW")
export COMPLETED_STORIES=($(for s in "${COMPLETED_STORIES[@]}"; do printf '%q ' "$s"; done))
EOF
echo "Env written: /tmp/oracle-work/env.02.sh"
