# Phase 00 — Auth, Project Discovery, Anchor Issue

## Step 0.0 — Auth

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
TARGET_ORG="${TARGET_ORG:-carespace-ai}"
gh auth status >/dev/null 2>&1 || { echo "BLOCKED: GITHUB_TOKEN invalid"; exit 1; }
```

## Step 0.1 — Find the anchor issue

Three modes, tried in order:

**Mode A** — `$CLAUDEHUB_INPUT_KWARGS` contains `project_slug`. Find the anchor by slug:

```bash
PROJECT_SLUG=$(echo "$CLAUDEHUB_INPUT_KWARGS" | jq -r '.project_slug // empty' 2>/dev/null)

if [ -n "$PROJECT_SLUG" ]; then
  ANCHOR_JSON=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label bmad --state open --limit 100 \
    --json number,title,labels)

  ANCHOR=$(echo "$ANCHOR_JSON" | jq -r --arg slug "$PROJECT_SLUG" '
    .[] | select(
      .labels[] | .name | ascii_downcase |
      gsub("[^a-z0-9]"; "-") | ltrimstr("-") | rtrimstr("-") |
      contains($slug)
    ) | .number' | head -1)

  [ -z "$ANCHOR" ] || [ "$ANCHOR" = "null" ] && {
    echo "BLOCKED: no open issue found for project_slug=$PROJECT_SLUG"
    exit 1
  }
  RESUME_MODE=false
fi
```

**Mode B** — No slug given. First check for failed runs (issues with `maestro:implementing`
but no active pipeline), then fall back to `maestro-ready` issues.

```bash
if [ -z "$PROJECT_SLUG" ]; then

  # ── Mode B1: resume a failed/orphaned run ─────────────────────────────────
  # Pick the first maestro:implementing issue whose feature branch has had no
  # commits in the last 90 minutes (i.e. no active run is writing to it).

  IMPLEMENTING_ISSUES=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label maestro:implementing --state open --limit 20 \
    --json number,title,labels)

  ANCHOR=""
  RESUME_MODE=false

  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] || [ "$issue_num" = "null" ] && continue

    # Derive slug from this issue's labels
    ISSUE_LABELS=$(gh issue view "$issue_num" \
      --repo "$TARGET_ORG/the-oracle-backlog" \
      --json labels | jq -r '.labels[].name')
    ISSUE_PROJECT_LABEL=$(echo "$ISSUE_LABELS" | grep "^project: " | head -1)
    ISSUE_SLUG=$(echo "$ISSUE_PROJECT_LABEL" | sed 's/^project: //' \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
    [ -z "$ISSUE_SLUG" ] && continue

    # Check if the feature branch has recent activity (within 90 min)
    BRANCH="feat/oracle-project-$ISSUE_SLUG"
    INVOLVED_REPOS_CHECK=($(gh api "repos/$TARGET_ORG/the-oracle-backlog/contents/bmad-context/$ISSUE_SLUG/feature-intent.json" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | jq -r '.involved_repos[].full_name | split("/")[1]' 2>/dev/null))

    BRANCH_ACTIVE=false
    for REPO_CHECK in "${INVOLVED_REPOS_CHECK[@]}"; do
      LAST_COMMIT_TIME=$(gh api "repos/$TARGET_ORG/$REPO_CHECK/commits?sha=$BRANCH&per_page=1" \
        --jq '.[0].commit.committer.date' 2>/dev/null)
      if [ -n "$LAST_COMMIT_TIME" ] && [ "$LAST_COMMIT_TIME" != "null" ]; then
        COMMIT_AGE=$(( $(date +%s) - $(date -d "$LAST_COMMIT_TIME" +%s 2>/dev/null || echo 0) ))
        [ "$COMMIT_AGE" -lt 5400 ] && { BRANCH_ACTIVE=true; break; }  # 90 min
      fi
    done

    if [ "$BRANCH_ACTIVE" = "false" ]; then
      ANCHOR="$issue_num"
      PROJECT_SLUG="$ISSUE_SLUG"
      RESUME_MODE=true
      echo "Mode B1: resuming failed run for issue #$issue_num (slug: $ISSUE_SLUG)"
      break
    else
      echo "Issue #$issue_num ($ISSUE_SLUG) has an active run — skipping"
    fi
  done < <(echo "$IMPLEMENTING_ISSUES" | jq -r '.[].number')

  # ── Mode B2: fresh start from maestro-ready ────────────────────────────────
  if [ -z "$ANCHOR" ]; then
    READY_JSON=$(gh issue list \
      --repo "$TARGET_ORG/the-oracle-backlog" \
      --label bmad --label maestro-ready \
      --state open --limit 1 \
      --json number,title,labels)

    ANCHOR=$(echo "$READY_JSON" | jq -r '.[0].number')
    [ -z "$ANCHOR" ] || [ "$ANCHOR" = "null" ] && {
      echo "BLOCKED: no open issues with maestro-ready and no resumable implementing issues"
      exit 0
    }
    RESUME_MODE=false
    echo "Mode B2: fresh start for issue #$ANCHOR"
  fi
fi
```

Both modes: resolve `PROJECT_NAME` and `PROJECT_SLUG` from the anchor issue's labels:

```bash
ANCHOR_LABELS=$(gh issue view "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --json labels | jq -r '.labels[].name')

PROJECT_LABEL=$(echo "$ANCHOR_LABELS" | grep "^project: " | head -1)
PROJECT_NAME=$(echo "$PROJECT_LABEL" | sed 's/^project: //')
PROJECT_SLUG="${PROJECT_SLUG:-$(echo "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')}"

echo "Anchor: #$ANCHOR | Project: $PROJECT_NAME | Slug: $PROJECT_SLUG | Resume: $RESUME_MODE"
[ -z "$PROJECT_SLUG" ] && { echo "BLOCKED: could not derive project slug from issue labels"; exit 1; }
```

## Step 0.2 — Mark pipeline as started (or confirm resume)

```bash
if [ "$RESUME_MODE" = "true" ]; then
  # Already has maestro:implementing — just leave a resume comment
  gh issue comment "$ANCHOR" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Oracle pipeline **resuming** for \`$PROJECT_NAME\` (previous run failed or was orphaned). Continuing from last committed story."
else
  gh issue edit "$ANCHOR" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --add-label maestro:implementing \
    --remove-label maestro-ready

  gh issue comment "$ANCHOR" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Oracle pipeline started for \`$PROJECT_NAME\`. Implementation beginning now."
fi
```

---

**Next:** Read `shards/phase-01-workspace.md`
