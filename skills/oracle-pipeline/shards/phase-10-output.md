# Phase 10 — Structured Output & Audit Log

## Structured JSON to stdout

```json
{
  "project_slug": "asset-management-system-ams",
  "project_label": "project: Asset Management System (AMS)",
  "anchor_issue_number": 286,
  "group_user_stories": [273, 274, 275],
  "stories_implemented": ["1.1", "1.2", "1.3", "2.1"],
  "prs": [
    {"repo": "carespace-admin", "url": "...", "sha": "abc123", "files_modified": [...]},
    {"repo": "carespace-ui",    "url": "...", "sha": "def456", "files_modified": [...]}
  ],
  "scope_deviations": [],
  "duration_seconds": 8421,
  "tokens_used": null,
  "failed_at_story": null
}
```

## Audit log lines (emit one per state transition to stdout)

```json
{"project_slug":"...","anchor_issue_number":286,"story_id":"1.2",
 "action":"story_committed","actor":"maestro-orchestrator",
 "timestamp":"2026-04-30T10:23:00Z","outcome":"success","cost_estimate":null}
```

Required actions: `project_picked_up`, `repos_cloned`, `branch_created`,
`story_committed`, `scope_audit_complete`, `pr_opened`, `deploy_dispatched`,
`pipeline_failed`, `pipeline_complete`.

## Final human-readable output

```
COMPLETE: project=<slug> anchor=#<N> group=[<list>]
PRs:
  <repo-1>: <url-1>
  <repo-2>: <url-2>
Stories: <N>/<N>
Scope deviations: <count>
Deploy dispatched: <yes|no>
```

Update PIPELINE.md `## Status` to `COMPLETE` (or
`COMPLETE_WITH_SCOPE_DEVIATIONS`).
