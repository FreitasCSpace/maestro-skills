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
