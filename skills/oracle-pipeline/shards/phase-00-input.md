# Phase 00 — Auth, Project Discovery, Anchor Issue

## Step 0.0 — Auth

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
TARGET_ORG="${TARGET_ORG:-carespace-ai}"
gh auth status >/dev/null 2>&1 || { echo "BLOCKED: GITHUB_TOKEN invalid"; exit 1; }
```

## Step 0.1 — Find the anchor issue

Issues in `the-oracle-backlog` carry `bmad` + `maestro-ready` + `project: <name>`.
One issue per project — it already exists, never create a new one.

**Mode A** — `$CLAUDEHUB_INPUT_KWARGS` contains `project_slug`. Find the anchor by slug:

```bash
# Find anchor issue matching the given slug
ANCHOR_JSON=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label bmad --label maestro-ready \
  --state open --limit 100 \
  --json number,title,labels)

ANCHOR=$(echo "$ANCHOR_JSON" | jq -r --arg slug "$PROJECT_SLUG" '
  .[] | select(
    .labels[] | .name | ascii_downcase |
    gsub("[^a-z0-9]"; "-") | ltrimstr("-") | rtrimstr("-") |
    contains($slug)
  ) | .number' | head -1)
```

**Mode B** — empty input. Pick the first eligible project:

```bash
if [ -z "$PROJECT_SLUG" ]; then
  ANCHOR_JSON=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label bmad --label maestro-ready \
    --state open --limit 1 \
    --json number,title,labels)

  ANCHOR=$(echo "$ANCHOR_JSON" | jq -r '.[0].number')
  [ -z "$ANCHOR" ] || [ "$ANCHOR" = "null" ] && {
    echo "BLOCKED: no open issues with bmad + maestro-ready"
    exit 1
  }
fi
```

Both modes: resolve `PROJECT_NAME` and `PROJECT_SLUG` from the anchor issue's labels:

```bash
ANCHOR_LABELS=$(gh issue view "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --json labels | jq -r '.labels[].name')

PROJECT_LABEL=$(echo "$ANCHOR_LABELS" | grep "^project: " | head -1)
PROJECT_NAME=$(echo "$PROJECT_LABEL" | sed 's/^project: //')
PROJECT_SLUG=$(echo "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')

echo "Anchor: #$ANCHOR | Project: $PROJECT_NAME | Slug: $PROJECT_SLUG"
[ -z "$PROJECT_SLUG" ] && { echo "BLOCKED: could not derive project slug from issue labels"; exit 1; }
```

## Step 0.2 — Mark pipeline as started

```bash
gh issue edit "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --add-label oracle:implementing \
  --remove-label maestro-ready

gh issue comment "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Oracle pipeline started for \`$PROJECT_NAME\`. Implementation beginning now."
```

---

**Next:** Read `shards/phase-01-workspace.md`
