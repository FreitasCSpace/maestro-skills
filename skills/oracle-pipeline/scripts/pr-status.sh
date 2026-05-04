#!/usr/bin/env bash
# pr-status.sh — show status of all PRs in the current Oracle project group
# via multi-gitter (lindell/multi-gitter).
#
# Reads env from /tmp/oracle-work (run after phases 00–04). For querying a
# project that has no local workspace, set ANCHOR / TARGET_ORG / BRANCH and
# INVOLVED_REPOS in the environment directly.
set -euo pipefail

[ -f /tmp/oracle-work/env.00.sh ] && . /tmp/oracle-work/env.00.sh
[ -f /tmp/oracle-work/env.01.sh ] && . /tmp/oracle-work/env.01.sh
[ -f /tmp/oracle-work/env.02.sh ] && . /tmp/oracle-work/env.02.sh

: "${BRANCH:?BRANCH must be set (run phase 00 first or export it)}"
: "${INVOLVED_REPOS:?INVOLVED_REPOS array must be set (run phase 01 first or export it)}"
: "${TARGET_ORG:?TARGET_ORG must be set}"

command -v multi-gitter >/dev/null 2>&1 \
  || { echo "BLOCKED: multi-gitter not on PATH. Install: go install github.com/lindell/multi-gitter@latest"; exit 1; }

REPOS=()
for r in "${INVOLVED_REPOS[@]}"; do REPOS+=("$TARGET_ORG/$r"); done

echo "Project: $PROJECT_SLUG (anchor #$ANCHOR)"
echo "Branch:  $BRANCH"
echo "Repos:   ${REPOS[*]}"
echo ""

multi-gitter status \
  --token "${GITHUB_TOKEN:?GITHUB_TOKEN required}" \
  --branch "$BRANCH" \
  --repo "$(IFS=,; echo "${REPOS[*]}")"
