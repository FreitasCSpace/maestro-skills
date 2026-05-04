#!/usr/bin/env bash
# reset-issue.sh — wipe a project's pipeline state and re-arm maestro-ready.
#
# What it does:
#   1. Resolves the project slug + involved repos from the anchor issue's
#      labels and BMAD context.
#   2. Closes all open PRs in the group via multi-gitter.
#   3. Deletes the remote feature branch in every involved repo.
#   4. Strips terminal labels and re-applies maestro-ready.
#
# Use this when an issue is stuck (deploying / blocked / blocked-*) and you
# want the next pipeline tick to start fresh.
#
# Usage:   reset-issue.sh <ISSUE_NUM>
# Env:     TARGET_ORG (default carespace-ai), GITHUB_TOKEN
set -euo pipefail

ISSUE="${1:?usage: reset-issue.sh <ISSUE_NUM>}"
TARGET_ORG="${TARGET_ORG:-carespace-ai}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${GITHUB_TOKEN:?GITHUB_TOKEN required}"
command -v multi-gitter >/dev/null 2>&1 \
  || { echo "BLOCKED: multi-gitter not on PATH"; exit 1; }

# Make sure labels exist before we try to manipulate them
"$SCRIPT_DIR/ensure-labels.sh" "$TARGET_ORG/the-oracle-backlog" || true

# Resolve project info
LABELS=$(gh issue view "$ISSUE" --repo "$TARGET_ORG/the-oracle-backlog" \
  --json labels --jq '.labels[].name')
PROJECT_LABEL=$(echo "$LABELS" | grep "^project: " | head -1 || true)
[ -z "$PROJECT_LABEL" ] && { echo "BLOCKED: issue #$ISSUE has no project: label"; exit 1; }
PROJECT_NAME=$(echo "$PROJECT_LABEL" | sed 's/^project: //')
PROJECT_SLUG=$(echo "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
SLUG_SHORT=$(echo "$PROJECT_SLUG" | cut -c1-40 | sed -E 's/-+$//')
BRANCH="feat/${ISSUE}-${SLUG_SHORT}"

# Pull involved repos from BMAD context (try main, then context branch)
INVOLVED=()
for REF in "main" "bmad/${PROJECT_SLUG}-context"; do
  RAW=$(gh api "repos/$TARGET_ORG/the-oracle-backlog/contents/bmad-context/$PROJECT_SLUG/feature-intent.json?ref=$REF" \
    --jq '.content' 2>/dev/null | base64 -d 2>/dev/null \
    | jq -r '.involved_repos[].full_name | split("/")[1]' 2>/dev/null || true)
  if [ -n "$RAW" ]; then
    while IFS= read -r r; do INVOLVED+=("$r"); done <<<"$RAW"
    break
  fi
done

if [ ${#INVOLVED[@]} -eq 0 ]; then
  echo "WARN: could not resolve INVOLVED_REPOS from BMAD context — skipping PR close + branch delete"
else
  echo "Project: $PROJECT_NAME"
  echo "Slug:    $PROJECT_SLUG"
  echo "Branch:  $BRANCH"
  echo "Repos:   ${INVOLVED[*]}"

  # Close PRs across the group via multi-gitter
  REPOS=()
  for r in "${INVOLVED[@]}"; do REPOS+=("$TARGET_ORG/$r"); done
  multi-gitter close \
    --token "$GITHUB_TOKEN" \
    --branch "$BRANCH" \
    --repo "$(IFS=,; echo "${REPOS[*]}")" \
    || echo "WARN: multi-gitter close had errors (PRs may already be closed)"

  # Delete remote feature branches
  for r in "${INVOLVED[@]}"; do
    if gh api -X DELETE "repos/$TARGET_ORG/$r/git/refs/heads/$BRANCH" --silent 2>/dev/null; then
      echo "Deleted $r:$BRANCH"
    else
      echo "Skipped $r:$BRANCH (not found or no permission)"
    fi
  done
fi

# Strip terminal labels and re-arm maestro-ready
gh issue edit "$ISSUE" --repo "$TARGET_ORG/the-oracle-backlog" \
  --remove-label maestro:implementing \
  --remove-label maestro:deploying \
  --remove-label maestro:merged \
  --remove-label maestro:blocked \
  --remove-label maestro:blocked-pipeline-failed \
  --remove-label maestro:blocked-spec-incomplete \
  --add-label maestro-ready 2>&1 \
  | grep -v "not found in" || true

gh issue comment "$ISSUE" --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Issue reset to \`maestro-ready\`. Previous PRs closed and feature branch \`$BRANCH\` deleted."

echo ""
echo "Issue #$ISSUE reset complete — next pipeline tick will pick it up."
