#!/usr/bin/env bash
# Phase 05 — Finalize: mark PIPELINE.md complete, fire optional webhook,
#            emit final human-readable + JSON output.
set -euo pipefail

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
. /tmp/oracle-work/env.02.sh
[ -f /tmp/oracle-work/env.04.sh ] && . /tmp/oracle-work/env.04.sh
declare -A PR_URLS=("${PR_URLS[@]:-}") 2>/dev/null || declare -A PR_URLS

HARD_FAILURES="${HARD_FAILURES:-0}"

sed -i 's/^## Status.*/## Status\nCOMPLETE/' /tmp/oracle-work/PIPELINE.md || true

# Final human-readable
echo ""
echo "COMPLETE: project=$PROJECT_SLUG anchor=#$ANCHOR"
echo "PRs:"
for REPO in "${!PR_URLS[@]}"; do
  echo "  $REPO: ${PR_URLS[$REPO]}"
done
echo "Hard failures: $HARD_FAILURES"
echo "Deploy dispatched: yes"

# Fire-and-forget webhook
if [ -n "${NOTIFICATION_WEBHOOK_URL:-}" ]; then
  PR_URLS_JSON=$(for REPO in "${!PR_URLS[@]}"; do
    printf '{"repo":"%s","url":"%s"}\n' "$REPO" "${PR_URLS[$REPO]}"
  done | jq -s .)

  PAYLOAD=$(jq -n \
    --arg project_slug "$PROJECT_SLUG" \
    --arg project_name "$PROJECT_NAME" \
    --argjson anchor "$ANCHOR" \
    --argjson hard_failures "$HARD_FAILURES" \
    --argjson prs "${PR_URLS_JSON:-[]}" \
    '{event:"oracle.pipeline.complete", project_slug:$project_slug,
      project_name:$project_name, anchor_issue:$anchor,
      hard_failures:$hard_failures, prs:$prs}')

  curl -sf -X POST "$NOTIFICATION_WEBHOOK_URL" \
    -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null 2>&1 \
    && echo "Notification sent" || echo "Notification failed (ignored)"
else
  echo "NOTIFICATION_WEBHOOK_URL not set — skipping"
fi
