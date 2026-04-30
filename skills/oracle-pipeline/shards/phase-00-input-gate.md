# Phase 00 — Input Gate & Project Discovery

## Step 0.0 — Input gate (do this FIRST)

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Two valid input modes:

**Mode A — orchestrator-driven.** `$CLAUDEHUB_INPUT_KWARGS` is JSON containing
at minimum `project_slug`. Example:

```json
{
  "project_slug": "asset-management-system-ams",
  "target_org": "carespace-ai",
  "anchor_issue_number": 286
}
```

`anchor_issue_number` is optional; resolved in phase-01-workspace.md step 0.4.

**Mode B — manual / auto-discovery.** Input is empty. Skill resolves
`project_slug` via 0.1 below.

`target_org` defaults to `carespace-ai`. `$GITHUB_TOKEN` must be set.

- If `$GITHUB_TOKEN` empty: `BLOCKED: GITHUB_TOKEN missing` → exit 1.
- If neither mode resolves a slug after 0.1: `BLOCKED: no eligible project
  found` → exit 1. Do not try alternative label names.

## Step 0.1 — Resolve project_slug (Mode B only)

```bash
gh auth status >/dev/null || { echo "BLOCKED: GITHUB_TOKEN invalid"; exit 1; }
TARGET_ORG="${TARGET_ORG:-carespace-ai}"

if [ -z "$PROJECT_SLUG" ]; then
  ELIGIBLE=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label maestro-ready --label user-story \
    --state open --limit 1000 \
    --json number,labels \
    | jq -r '
      [.[] | .labels[] | select(.name | startswith("project:"))]
      | group_by(.name) | map({label: .[0].name, count: length})
      | sort_by(-.count) | .[]
      | "\(.count)\t\(.label)"
    ')

  [ -z "$ELIGIBLE" ] && { echo "BLOCKED: no eligible project found"; exit 1; }

  # Pick the project with the most ready stories
  TOP_LABEL=$(echo "$ELIGIBLE" | head -1 | cut -f2- | sed 's/^project: //')
  PROJECT_SLUG=$(echo "$TOP_LABEL" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
  echo "Auto-selected project: $TOP_LABEL → slug=$PROJECT_SLUG"
fi

# Canonical label string for all downstream issue searches
PROJECT_LABEL="project:${TOP_LABEL:-$PROJECT_SLUG_TITLE}"
```

If orchestrator passed `project_slug` without the label string, derive it by
listing labels matching `project:*` and selecting the one whose slugified value
matches `$PROJECT_SLUG`. No match → exit 1 with
`BLOCKED: no project label matches slug '$PROJECT_SLUG'`.

---

**Next:** Read `shards/phase-01-workspace.md`
