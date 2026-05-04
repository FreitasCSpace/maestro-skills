#!/usr/bin/env bash
# pr-close-group.sh — close every PR in the current Oracle project group
# via multi-gitter. Used by reset-issue.sh and for manual aborts.
#
# Does NOT delete branches — see reset-issue.sh for the full reset.
set -euo pipefail

[ -f /tmp/oracle-work/env.00.sh ] && . /tmp/oracle-work/env.00.sh
[ -f /tmp/oracle-work/env.01.sh ] && . /tmp/oracle-work/env.01.sh
[ -f /tmp/oracle-work/env.02.sh ] && . /tmp/oracle-work/env.02.sh

: "${BRANCH:?BRANCH must be set}"
: "${INVOLVED_REPOS:?INVOLVED_REPOS must be set}"
: "${TARGET_ORG:?TARGET_ORG must be set}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN required}"

command -v multi-gitter >/dev/null 2>&1 \
  || { echo "BLOCKED: multi-gitter not on PATH"; exit 1; }

REPOS=()
for r in "${INVOLVED_REPOS[@]}"; do REPOS+=("$TARGET_ORG/$r"); done

multi-gitter close \
  --token "$GITHUB_TOKEN" \
  --branch "$BRANCH" \
  --repo "$(IFS=,; echo "${REPOS[*]}")" \
  || echo "WARN: some PRs may already be closed"
