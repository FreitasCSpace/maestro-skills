#!/usr/bin/env bash
# Phase 01 — Workspace, BMAD context, story extraction.
#
# Reads: env from phase 00 (TARGET_ORG, ANCHOR, PROJECT_SLUG)
# Writes:
#   /tmp/oracle-work/backlog/                 — cloned backlog
#   /tmp/oracle-work/stories-order.txt        — tab-sep epic/story/title order
#   /tmp/oracle-work/story-meta/N-M.sh        — per-story metadata
#   /tmp/oracle-work/env.01.sh                — INVOLVED_REPOS, PLANNING_DIR
set -euo pipefail

ENV_IN="${1:-/tmp/oracle-work/env.00.sh}"
[ -f "$ENV_IN" ] && . "$ENV_IN"

: "${TARGET_ORG:?}" "${ANCHOR:?}" "${PROJECT_SLUG:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

rm -rf /tmp/oracle-work 2>/dev/null || true
mkdir -p /tmp/oracle-work/workspace /tmp/oracle-work/stories /tmp/oracle-work/story-meta
cd /tmp/oracle-work

# Clone backlog main, fall back to context branch for the bmad-context dir
gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- --depth=1
cd backlog
CTX_DIR="bmad-context/$PROJECT_SLUG"

if [ ! -d "$CTX_DIR" ]; then
  CONTEXT_BRANCH="bmad/${PROJECT_SLUG}-context"
  if git fetch origin "$CONTEXT_BRANCH" 2>/dev/null \
     && git checkout "origin/$CONTEXT_BRANCH" -- "$CTX_DIR" 2>/dev/null; then
    echo "Context fetched from $CONTEXT_BRANCH"
  else
    cd /tmp/oracle-work
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "BMAD context not found on main or on branch \`$CONTEXT_BRANCH\` — aborting"
    gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --remove-label maestro:implementing --add-label maestro:blocked-pipeline-failed
    exit 1
  fi
else
  echo "Context found on main"
fi
cd /tmp/oracle-work

PLANNING_DIR="/tmp/oracle-work/backlog/bmad-context/$PROJECT_SLUG"
for f in feature-intent.json stories-output.md; do
  [ -f "$PLANNING_DIR/$f" ] || {
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "Missing required BMAD file: \`$f\`"
    exit 1; }
done

INVOLVED_REPOS=($(jq -r '.involved_repos[].full_name | split("/")[1]' \
  "$PLANNING_DIR/feature-intent.json"))
[ ${#INVOLVED_REPOS[@]} -gt 0 ] || { echo "BLOCKED: no involved_repos"; exit 1; }
echo "Involved repos: ${INVOLVED_REPOS[*]}"

# Parse stories via shipped python script
python3 "$SKILL_DIR/resources/extract-stories.py" \
  "$PLANNING_DIR/stories-output.md" \
  /tmp/oracle-work/story-meta \
  /tmp/oracle-work/stories-order.txt

TOTAL=$(grep -c . /tmp/oracle-work/stories-order.txt 2>/dev/null || echo 0)
[ "$TOTAL" -gt 0 ] || { echo "BLOCKED: no stories parsed"; exit 1; }
echo "Extracted $TOTAL stories"

cat > /tmp/oracle-work/env.01.sh <<EOF
export PLANNING_DIR=$(printf %q "$PLANNING_DIR")
export INVOLVED_REPOS=($(for r in "${INVOLVED_REPOS[@]}"; do printf '%q ' "$r"; done))
export TOTAL_STORIES=$(printf %q "$TOTAL")
EOF
echo "Env written: /tmp/oracle-work/env.01.sh"
