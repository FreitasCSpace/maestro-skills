#!/usr/bin/env bash
# ensure-labels.sh — idempotently create the maestro:* label set on a repo.
# Usage: ensure-labels.sh [<REPO>]
set -euo pipefail

REPO="${1:-${TARGET_ORG:-carespace-ai}/the-oracle-backlog}"

ensure_label() {
  local name="$1" color="$2" desc="$3"
  if ! gh api "repos/$REPO/labels/${name// /%20}" --silent 2>/dev/null; then
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" 2>/dev/null \
      || echo "WARN: could not create label '$name' on $REPO (may already exist or insufficient perms)"
  fi
}

ensure_label "maestro-ready"                   "0E8A16" "Oracle pipeline: ready to start"
ensure_label "maestro:implementing"            "FBCA04" "Oracle pipeline: actively implementing"
ensure_label "maestro:deploying"               "0E8A16" "Oracle pipeline: PRs opened, awaiting deployment"
ensure_label "maestro:merged"                  "5319E7" "Oracle pipeline: PR group merged via pr-merge-group.sh"
ensure_label "maestro:blocked"                 "B60205" "Oracle pipeline: aborted (PIPELINE_RUNAWAY ≥ 5 failures)"
ensure_label "maestro:blocked-pipeline-failed" "B60205" "Oracle pipeline: BMAD context missing or workflow broken"
ensure_label "maestro:blocked-spec-incomplete" "B60205" "Oracle pipeline: anchor issue body fails the spec gate"

echo "Labels ensured on $REPO"
