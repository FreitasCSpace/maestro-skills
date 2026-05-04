#!/usr/bin/env bash
# Phase 00 — Auth, project discovery, anchor issue.
#
# Resolves: ANCHOR, PROJECT_NAME, PROJECT_SLUG, RESUME_MODE
# Emits a sourceable env file at $1 (default /tmp/oracle-work/env.00.sh).
#
# Modes (tried in order):
#   A. CLAUDEHUB_INPUT_KWARGS contains project_slug -> match by slug label.
#   B1. No slug, but maestro:implementing issue exists with stale branch -> resume.
#   B2. Else, first maestro-ready issue -> fresh start.
set -euo pipefail

OUT_ENV="${1:-/tmp/oracle-work/env.00.sh}"
mkdir -p "$(dirname "$OUT_ENV")"

TARGET_ORG="${TARGET_ORG:-carespace-ai}"
gh auth status >/dev/null 2>&1 || { echo "BLOCKED: GITHUB_TOKEN invalid"; exit 1; }

PROJECT_SLUG=$(echo "${CLAUDEHUB_INPUT_KWARGS:-}" | jq -r '.project_slug // empty' 2>/dev/null || echo "")
ANCHOR=""
RESUME_MODE=false

# ── Mode A: project_slug provided ────────────────────────────────────────────
if [ -n "$PROJECT_SLUG" ]; then
  ANCHOR=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label bmad --state open --limit 100 \
    --json number,title,labels \
    | jq -r --arg slug "$PROJECT_SLUG" '
        .[] | select(
          .labels[] | .name | ascii_downcase
          | gsub("[^a-z0-9]"; "-")
          | ltrimstr("-") | rtrimstr("-")
          | contains($slug)
        ) | .number' | head -1)

  [ -z "$ANCHOR" ] || [ "$ANCHOR" = "null" ] && {
    echo "BLOCKED: no open issue found for project_slug=$PROJECT_SLUG"; exit 1; }
fi

# ── Mode B1: resume orphaned maestro:implementing issue ──────────────────────
if [ -z "$ANCHOR" ]; then
  IMPLEMENTING=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label maestro:implementing --state open --limit 20 \
    --json number)

  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] || [ "$issue_num" = "null" ] && continue

    LABELS=$(gh issue view "$issue_num" --repo "$TARGET_ORG/the-oracle-backlog" \
      --json labels | jq -r '.labels[].name')
    PROJECT_LABEL=$(echo "$LABELS" | grep "^project: " | head -1 || true)
    ISSUE_SLUG=$(echo "$PROJECT_LABEL" | sed 's/^project: //' \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
    [ -z "$ISSUE_SLUG" ] && continue

    SLUG_SHORT=$(echo "$ISSUE_SLUG" | cut -c1-40 | sed -E 's/-+$//')
    BRANCH="feat/${issue_num}-${SLUG_SHORT}"
    REPOS=($(gh api "repos/$TARGET_ORG/the-oracle-backlog/contents/bmad-context/$ISSUE_SLUG/feature-intent.json" \
      --jq '.content' 2>/dev/null | base64 -d 2>/dev/null \
      | jq -r '.involved_repos[].full_name | split("/")[1]' 2>/dev/null || true))

    BRANCH_ACTIVE=false
    for REPO in "${REPOS[@]}"; do
      LAST=$(gh api "repos/$TARGET_ORG/$REPO/commits?sha=$BRANCH&per_page=1" \
        --jq '.[0].commit.committer.date' 2>/dev/null || echo "")
      if [ -n "$LAST" ] && [ "$LAST" != "null" ]; then
        AGE=$(( $(date +%s) - $(date -d "$LAST" +%s 2>/dev/null || echo 0) ))
        [ "$AGE" -lt 5400 ] && { BRANCH_ACTIVE=true; break; }
      fi
    done

    if [ "$BRANCH_ACTIVE" = "false" ]; then
      ANCHOR="$issue_num"
      PROJECT_SLUG="$ISSUE_SLUG"
      RESUME_MODE=true
      echo "Mode B1: resuming failed run for issue #$issue_num (slug: $ISSUE_SLUG)"
      break
    fi
    echo "Issue #$issue_num ($ISSUE_SLUG) has an active run — skipping"
  done < <(echo "$IMPLEMENTING" | jq -r '.[].number')
fi

# ── Mode B2: fresh start from maestro-ready ──────────────────────────────────
if [ -z "$ANCHOR" ]; then
  ANCHOR=$(gh issue list --repo "$TARGET_ORG/the-oracle-backlog" \
    --label bmad --label maestro-ready --state open --limit 1 \
    --json number | jq -r '.[0].number')

  [ -z "$ANCHOR" ] || [ "$ANCHOR" = "null" ] && {
    echo "BLOCKED: no maestro-ready issues and no resumable runs"; exit 0; }
  echo "Mode B2: fresh start for issue #$ANCHOR"
fi

# Resolve PROJECT_NAME and PROJECT_SLUG from anchor labels
LABELS=$(gh issue view "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
  --json labels | jq -r '.labels[].name')
PROJECT_LABEL=$(echo "$LABELS" | grep "^project: " | head -1 || true)
PROJECT_NAME=$(echo "$PROJECT_LABEL" | sed 's/^project: //')
PROJECT_SLUG="${PROJECT_SLUG:-$(echo "$PROJECT_NAME" \
  | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')}"

[ -z "$PROJECT_SLUG" ] && { echo "BLOCKED: could not derive project slug from issue labels"; exit 1; }
echo "Anchor: #$ANCHOR | Project: $PROJECT_NAME | Slug: $PROJECT_SLUG | Resume: $RESUME_MODE"

# ── Issue-spec gate (rule 2): refuse to run if issue is not a usable spec ────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! "$SCRIPT_DIR/validate-issue-spec.sh" "$ANCHOR" "$TARGET_ORG/the-oracle-backlog" 2>&1 | tee /tmp/oracle-issue-validate.log; then
  REASON=$(grep -E '^  - ' /tmp/oracle-issue-validate.log || echo "  - issue body is not a usable spec")
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "$(printf 'Oracle pipeline **blocked**: the issue body is not a sufficient spec.\n\nFailures:\n%s\n\nThe issue is the input of the pipeline. It must describe business rules and acceptance criteria in functional language so any engineer could re-implement the feature from the issue alone. Edit the issue and re-add the `maestro-ready` label.' "$REASON")"
  gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label maestro-ready --add-label maestro:blocked-spec-incomplete || true
  exit 1
fi

# Branch name (rule 1): feat/<ISSUE>-<short-slug>
SLUG_SHORT=$(echo "$PROJECT_SLUG" | cut -c1-40 | sed -E 's/-+$//')
BRANCH="feat/${ANCHOR}-${SLUG_SHORT}"

# Mark pipeline started or confirm resume
if [ "$RESUME_MODE" = "true" ]; then
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Oracle pipeline **resuming** for \`$PROJECT_NAME\` (branch \`$BRANCH\`). Continuing from last committed story."
else
  gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --add-label maestro:implementing --remove-label maestro-ready
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Oracle pipeline started for \`$PROJECT_NAME\` on branch \`$BRANCH\`. Implementation beginning now."
fi

# Emit sourceable env
cat > "$OUT_ENV" <<EOF
export TARGET_ORG=$(printf %q "$TARGET_ORG")
export ANCHOR=$(printf %q "$ANCHOR")
export PROJECT_NAME=$(printf %q "$PROJECT_NAME")
export PROJECT_SLUG=$(printf %q "$PROJECT_SLUG")
export PROJECT_LABEL=$(printf %q "$PROJECT_LABEL")
export RESUME_MODE=$(printf %q "$RESUME_MODE")
export BRANCH=$(printf %q "$BRANCH")
EOF
echo "Env written: $OUT_ENV (branch: $BRANCH)"
