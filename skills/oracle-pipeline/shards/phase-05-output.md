# Phase 05 — Structured Output

Update PIPELINE.md status and emit final JSON to stdout.

```bash
sed -i 's/^## Status.*/## Status\nCOMPLETE/' /tmp/oracle-work/PIPELINE.md
```

## Structured JSON

```json
{
  "project_slug": "<slug>",
  "project_label": "<project: Name>",
  "anchor_issue_number": 405,
  "involved_repos": ["carespace-admin", "carespace-ui", "carespace-strapi"],
  "stories_implemented": ["1.1", "1.2", "2.1"],
  "stories_failed": [],
  "prs": [
    {"repo": "carespace-admin", "url": "...", "sha": "abc123"},
    {"repo": "carespace-ui",    "url": "...", "sha": "def456"}
  ],
  "hard_failures": 0,
  "deploy_dispatched": true
}
```

## Audit log lines (one per story, to stdout)

```json
{"project_slug":"...","anchor_issue":405,"story":"1.1",
 "action":"story_complete","timestamp":"...","outcome":"success"}
```

## Final human-readable output

```
COMPLETE: project=<slug> anchor=#<N>
PRs:
  <repo>: <url>
Stories: <N>/<N> implemented
Hard failures: <N>
Deploy dispatched: yes
```

## Notification webhook (optional)

Fire-and-forget POST to `NOTIFICATION_WEBHOOK_URL` if set. Used to ping the
ClaudeHub session (or Slack) that the background pipeline has finished.
Failures are ignored — never abort the pipeline on a notification error.

```bash
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
    '{
      event:          "oracle.pipeline.complete",
      project_slug:   $project_slug,
      project_name:   $project_name,
      anchor_issue:   $anchor,
      hard_failures:  $hard_failures,
      prs:            $prs
    }')

  curl -sf -X POST "$NOTIFICATION_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null 2>&1 || true
  echo "Notification sent to NOTIFICATION_WEBHOOK_URL"
else
  echo "NOTIFICATION_WEBHOOK_URL not set — skipping notification"
fi
```
