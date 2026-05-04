#!/usr/bin/env bash
# pr-merge-group.sh — merge every PR in the current Oracle project group
# via multi-gitter, then flip the anchor issue to maestro:merged.
#
# Pre-conditions (caller / human responsibility, not enforced here):
#   - All PRs (develop + master/main) are approved
#   - All required CI is green
#   - Manual smoke-test items in the PR body have been ticked by a human
#
# Usage:  pr-merge-group.sh [<merge-type>]
# merge-type: squash (default) | merge | rebase
set -euo pipefail

MERGE_TYPE="${1:-squash}"

[ -f /tmp/oracle-work/env.00.sh ] && . /tmp/oracle-work/env.00.sh
[ -f /tmp/oracle-work/env.01.sh ] && . /tmp/oracle-work/env.01.sh
[ -f /tmp/oracle-work/env.02.sh ] && . /tmp/oracle-work/env.02.sh

: "${BRANCH:?BRANCH must be set}"
: "${INVOLVED_REPOS:?INVOLVED_REPOS must be set}"
: "${TARGET_ORG:?TARGET_ORG must be set}"
: "${ANCHOR:?ANCHOR must be set}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN required}"

command -v multi-gitter >/dev/null 2>&1 \
  || { echo "BLOCKED: multi-gitter not on PATH"; exit 1; }

REPOS=()
for r in "${INVOLVED_REPOS[@]}"; do REPOS+=("$TARGET_ORG/$r"); done

echo "Merging PR group for $PROJECT_SLUG (#$ANCHOR) — branch $BRANCH, type=$MERGE_TYPE"
multi-gitter merge \
  --token "$GITHUB_TOKEN" \
  --branch "$BRANCH" \
  --repo "$(IFS=,; echo "${REPOS[*]}")" \
  --merge-type "$MERGE_TYPE"

# Flip anchor label
gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
  --remove-label maestro:deploying --add-label maestro:merged \
  || echo "WARN: anchor label flip failed (labels may need ensure-labels.sh)"

gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "PR group for \`$PROJECT_SLUG\` merged via multi-gitter ($MERGE_TYPE). Branch: \`$BRANCH\`."
