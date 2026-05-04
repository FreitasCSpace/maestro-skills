#!/usr/bin/env bash
# Phase 04 — Push, render PR body from test-plan rollup, open dual PRs
# (develop + master/main) per repo, comment on anchor, dispatch deploy.
#
# Rule 3: from a single feature branch, two PRs must be open simultaneously —
# one targeting develop, one targeting master. Both reference Closes #NNN.
set -euo pipefail

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
. /tmp/oracle-work/env.02.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PR_TPL="$SKILL_DIR/templates/pr-body.template.md"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
ANCHOR_URL="https://github.com/$TARGET_ORG/the-oracle-backlog/issues/$ANCHOR"

cd /tmp/oracle-work
PR_TITLE="[#$ANCHOR] $PROJECT_NAME"

# ── Aggregate test-plan results from per-story JSONL ────────────────────────
STORIES_JSONL="/tmp/oracle-work/test-plan/stories.jsonl"
LINT_MARK=" "; TESTS_MARK=" "; COVERAGE_MARK=" "; ACCEPTANCE_MARK=" "; REVIEW_MARK=" "
STORIES_LIST="(none committed)"
FAILED_COUNT=0

if [ -f "$STORIES_JSONL" ]; then
  TOTAL=$(grep -c . "$STORIES_JSONL" || echo 0)
  COMMITTED=$(jq -s '[.[] | select(.status=="committed")] | length' "$STORIES_JSONL")
  FAILED_COUNT=$(jq -s '[.[] | select(.status!="committed")] | length' "$STORIES_JSONL")

  ALL_LINT_PASS=$(jq -s '[.[] | select(.status=="committed") | .lint] | all(. == "pass")' "$STORIES_JSONL")
  ALL_COV_PASS=$(jq -s  '[.[] | select(.status=="committed") | .coverage] | all(. == "pass")' "$STORIES_JSONL")
  ALL_REV_PASS=$(jq -s  '[.[] | select(.status=="committed") | .review] | all(. == "approved")' "$STORIES_JSONL")

  [ "$ALL_LINT_PASS" = "true" ] && [ "$COMMITTED" -gt 0 ] && LINT_MARK="x"
  [ "$ALL_COV_PASS"  = "true" ] && [ "$COMMITTED" -gt 0 ] && { TESTS_MARK="x"; COVERAGE_MARK="x"; }
  [ "$ALL_REV_PASS"  = "true" ] && [ "$COMMITTED" -gt 0 ] && REVIEW_MARK="x"
  # Acceptance criteria considered met iff dev + review both pass
  [ "$LINT_MARK" = "x" ] && [ "$REVIEW_MARK" = "x" ] && ACCEPTANCE_MARK="x"

  STORIES_LIST=$(jq -r 'select(.status=="committed") | "- `\(.story_key)` — \(.title)"' "$STORIES_JSONL")
fi

IMPL_NOTES="${IMPLEMENTATION_NOTES:-_(none provided)_}"
PIPELINE_LINK="${PIPELINE_RUN_URL:-_(local run)_}"

render_pr_body() {
  sed \
    -e "s|__SLUG__|$PROJECT_SLUG|g" \
    -e "s|__ANCHOR__|$ANCHOR|g" \
    -e "s|__ANCHOR_URL__|$ANCHOR_URL|g" \
    -e "s|__LINT_MARK__|$LINT_MARK|g" \
    -e "s|__TESTS_MARK__|$TESTS_MARK|g" \
    -e "s|__COVERAGE_MARK__|$COVERAGE_MARK|g" \
    -e "s|__ACCEPTANCE_MARK__|$ACCEPTANCE_MARK|g" \
    -e "s|__REVIEW_MARK__|$REVIEW_MARK|g" \
    -e "s|__COV_THRESHOLD__|$COVERAGE_THRESHOLD|g" \
    -e "s|__FAILED_COUNT__|$FAILED_COUNT|g" \
    -e "s|__PIPELINE_LINK__|$PIPELINE_LINK|g" \
    "$PR_TPL" \
  | awk -v stories="$STORIES_LIST" -v notes="$IMPL_NOTES" '
      /__STORIES_LIST__/        { print stories; next }
      /__IMPLEMENTATION_NOTES__/{ print notes;   next }
      { print }
    '
}

# ── Detect target branches per repo (rule 3: dual PRs to develop + master) ──
detect_targets() {
  local repo="$1"
  local has_develop has_master has_main targets=()
  has_develop=$(gh api "repos/$TARGET_ORG/$repo/branches/develop" --silent 2>/dev/null && echo yes || echo no)
  has_master=$(gh api  "repos/$TARGET_ORG/$repo/branches/master"  --silent 2>/dev/null && echo yes || echo no)
  has_main=$(gh api    "repos/$TARGET_ORG/$repo/branches/main"    --silent 2>/dev/null && echo yes || echo no)
  [ "$has_develop" = "yes" ] && targets+=("develop")
  if [ "$has_master" = "yes" ]; then targets+=("master")
  elif [ "$has_main" = "yes" ]; then targets+=("main")
  fi
  printf '%s\n' "${targets[@]}"
}

declare -A PR_URLS_BY_REPO_TARGET   # key: <repo>:<target>
PR_BODY=$(render_pr_body)
LABELS="oracle-project,group:project-$PROJECT_SLUG,$PROJECT_LABEL"

for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"

  # Push branch (rule 1: branch already named feat/<ANCHOR>-<slug> by phase 00/02)
  if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    echo "No local branch $BRANCH in $REPO — skipping"; cd /tmp/oracle-work; continue
  fi

  DEFAULT=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
  DEFAULT="${DEFAULT:-master}"
  if git diff --quiet "origin/$DEFAULT..HEAD" 2>/dev/null; then
    echo "No changes in $REPO — skipping PR"; cd /tmp/oracle-work; continue
  fi
  git push --force-with-lease -u origin "$BRANCH"

  TARGETS=($(detect_targets "$REPO"))
  if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "WARN: no develop/master/main on $REPO — skipping PR"; cd /tmp/oracle-work; continue
  fi

  for TARGET in "${TARGETS[@]}"; do
    EXISTING=$(gh pr list --repo "$TARGET_ORG/$REPO" \
      --head "$BRANCH" --base "$TARGET" --state open --json number,url | jq '.[0]')

    if [ "$EXISTING" != "null" ] && [ -n "$EXISTING" ]; then
      PR_NUM=$(echo "$EXISTING" | jq -r .number)
      gh pr edit "$PR_NUM" --repo "$TARGET_ORG/$REPO" \
        --title "$PR_TITLE" --body "$PR_BODY" --add-label "$LABELS"
      PR_URL=$(echo "$EXISTING" | jq -r .url)
    else
      PR_URL=$(gh pr create --repo "$TARGET_ORG/$REPO" \
        --base "$TARGET" --head "$BRANCH" \
        --title "$PR_TITLE" --body "$PR_BODY" \
        --label "$LABELS")
    fi

    PR_URLS_BY_REPO_TARGET["$REPO:$TARGET"]="$PR_URL"
    echo "PR for $REPO -> $TARGET: $PR_URL"
  done

  cd /tmp/oracle-work
done

# Anchor comment with full PR list grouped by repo
PR_LIST=""
for REPO in "${INVOLVED_REPOS[@]}"; do
  REPO_LINES=""
  for KEY in "${!PR_URLS_BY_REPO_TARGET[@]}"; do
    case "$KEY" in
      "$REPO:"*)
        TARGET="${KEY#*:}"
        REPO_LINES="$REPO_LINES"$'\n'"  - → \`$TARGET\`: ${PR_URLS_BY_REPO_TARGET[$KEY]}"
      ;;
    esac
  done
  [ -n "$REPO_LINES" ] && PR_LIST="$PR_LIST"$'\n'"- **$REPO**$REPO_LINES"
done

gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "$(printf 'Pipeline complete for `%s` (#%s).\n\nPRs opened (each repo opens BOTH develop + master/main from the same branch — both must be approved before merge):%s' "$PROJECT_SLUG" "$ANCHOR" "$PR_LIST")"

gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
  --remove-label maestro:implementing --add-label maestro:deploying

# Trigger ephemeral deploy
INVOLVED_REPOS_JSON=$(printf '%s\n' "${INVOLVED_REPOS[@]}" | jq -R . | jq -s .)
gh api "repos/$TARGET_ORG/infra/dispatches" \
  --method POST \
  --field event_type='oracle.project.complete' \
  --field "client_payload[project_slug]=$PROJECT_SLUG" \
  --field "client_payload[anchor_issue_number]=$ANCHOR" \
  --field "client_payload[involved_repos]=$INVOLVED_REPOS_JSON" \
  --field "client_payload[bmad_context_path]=bmad-context/$PROJECT_SLUG"

# Persist for phase 05 (flatten to a simple "repo|target|url" list)
{
  echo "declare -A PR_URLS_BY_REPO_TARGET"
  for KEY in "${!PR_URLS_BY_REPO_TARGET[@]}"; do
    printf 'PR_URLS_BY_REPO_TARGET[%q]=%q\n' "$KEY" "${PR_URLS_BY_REPO_TARGET[$KEY]}"
  done
} > /tmp/oracle-work/env.04.sh
echo "Env written: /tmp/oracle-work/env.04.sh"
