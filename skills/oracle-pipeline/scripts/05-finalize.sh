#!/usr/bin/env bash
# Phase 05 — Finalize: mark PIPELINE.md complete, fire optional webhook,
#            emit final human-readable + JSON output.
set -euo pipefail

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
. /tmp/oracle-work/env.02.sh
declare -A PR_URLS_BY_REPO_TARGET
[ -f /tmp/oracle-work/env.04.sh ] && . /tmp/oracle-work/env.04.sh

HARD_FAILURES="${HARD_FAILURES:-0}"

sed -i 's/^## Status.*/## Status\nCOMPLETE/' /tmp/oracle-work/PIPELINE.md || true

# Final human-readable
echo ""
echo "COMPLETE: project=$PROJECT_SLUG anchor=#$ANCHOR branch=$BRANCH"
echo "PRs:"
for KEY in "${!PR_URLS_BY_REPO_TARGET[@]}"; do
  echo "  $KEY: ${PR_URLS_BY_REPO_TARGET[$KEY]}"
done
echo "Hard failures: $HARD_FAILURES"
echo "Deploy dispatched: yes"

# Fire-and-forget webhook
if [ -n "${NOTIFICATION_WEBHOOK_URL:-}" ]; then
  PR_URLS_JSON=$(for KEY in "${!PR_URLS_BY_REPO_TARGET[@]}"; do
    REPO="${KEY%%:*}"; TARGET="${KEY#*:}"
    printf '{"repo":"%s","target":"%s","url":"%s"}\n' "$REPO" "$TARGET" "${PR_URLS_BY_REPO_TARGET[$KEY]}"
  done | jq -s .)

  PAYLOAD=$(jq -n \
    --arg project_slug "$PROJECT_SLUG" \
    --arg project_name "$PROJECT_NAME" \
    --arg branch "$BRANCH" \
    --argjson anchor "$ANCHOR" \
    --argjson hard_failures "$HARD_FAILURES" \
    --argjson prs "${PR_URLS_JSON:-[]}" \
    '{event:"oracle.pipeline.complete", project_slug:$project_slug,
      project_name:$project_name, branch:$branch, anchor_issue:$anchor,
      hard_failures:$hard_failures, prs:$prs}')

  curl -sf -X POST "$NOTIFICATION_WEBHOOK_URL" \
    -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null 2>&1 \
    && echo "Notification sent" || echo "Notification failed (ignored)"
else
  echo "NOTIFICATION_WEBHOOK_URL not set — skipping"
fi
