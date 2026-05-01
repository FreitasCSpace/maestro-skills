# Phase 00 — Auth, Project Discovery, Anchor Issue

## Step 0.0 — Auth

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
TARGET_ORG="${TARGET_ORG:-carespace-ai}"
gh auth status >/dev/null 2>&1 || { echo "BLOCKED: GITHUB_TOKEN invalid"; exit 1; }
```

## Step 0.1 — Resolve project slug

**Mode A** — `$CLAUDEHUB_INPUT_KWARGS` contains `project_slug`. Use it directly.

**Mode B** — empty input. Discover via one gh call:

```bash
if [ -z "$PROJECT_SLUG" ]; then
  ELIGIBLE=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label maestro-ready \
    --state open --limit 1000 \
    --json number,labels \
    | jq -r '
      [.[] | .labels[] | select(.name | startswith("project:"))]
      | group_by(.name) | map({label: .[0].name, count: length})
      | sort_by(-.count) | .[0]
      | "\(.label)"
    ')
  [ -z "$ELIGIBLE" ] && { echo "BLOCKED: no eligible project found"; exit 1; }

  PROJECT_NAME=$(echo "$ELIGIBLE" | sed 's/^project: //')
  PROJECT_SLUG=$(echo "$PROJECT_NAME" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
  echo "Auto-selected: $PROJECT_NAME → $PROJECT_SLUG"
fi

PROJECT_LABEL="project: $PROJECT_NAME"
```

## Step 0.2 — Find or create the anchor issue

One issue per project. Find existing or create it.

```bash
ANCHOR=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label "$(echo "$PROJECT_LABEL")" \
  --label maestro-ready \
  --state open --limit 1 \
  --json number | jq -r '.[0].number // empty')

if [ -z "$ANCHOR" ]; then
  # No anchor exists yet — create one (body filled after stories-index is built in phase-01)
  ANCHOR=$(gh issue create \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --title "[Oracle Project] $PROJECT_NAME" \
    --body "Project pipeline pending — stories loading..." \
    --label "$PROJECT_LABEL" --label maestro-ready \
    | grep -oE '[0-9]+$')
  echo "Created anchor issue #$ANCHOR"
else
  echo "Using existing anchor issue #$ANCHOR"
fi
```

## Step 0.3 — Mark pipeline as started

```bash
gh issue edit "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --add-label oracle:implementing \
  --remove-label maestro-ready

gh issue comment "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Oracle pipeline started for \`$PROJECT_LABEL\`. Implementation beginning now."
```

---

**Next:** Read `shards/phase-01-workspace.md`
