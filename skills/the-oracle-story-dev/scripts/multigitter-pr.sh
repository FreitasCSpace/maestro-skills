#!/usr/bin/env bash
# Open one PR per repo in repos_affected via multi-gitter, with gh fallback.
#
# The branch is already pushed by Step 5 in SKILL.md. This wrapper just opens PRs.
# Each PR title and body is derived from the story.json metadata.

set -euo pipefail

WORKSPACE=""
BRANCH=""
STORY_JSON=""
BASE="develop"
OUT_FILE="/tmp/pr-urls.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)  WORKSPACE="$2"; shift 2 ;;
    --branch)     BRANCH="$2"; shift 2 ;;
    --story-json) STORY_JSON="$2"; shift 2 ;;
    --base)       BASE="$2"; shift 2 ;;
    --out)        OUT_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$WORKSPACE" || -z "$BRANCH" || -z "$STORY_JSON" ]] && {
  echo "usage: $0 --workspace <dir> --branch <name> --story-json <path> [--base develop] [--out /tmp/pr-urls.txt]" >&2
  exit 2
}

[[ -f "$STORY_JSON" ]] || { echo "story.json not found: $STORY_JSON" >&2; exit 1; }

STORY_ID=$(jq -r .id "$STORY_JSON")
STORY_TITLE=$(jq -r .story_title "$STORY_JSON")
FEATURE=$(jq -r .feature "$STORY_JSON")
FRS=$(jq -r '.frs_covered | join(", ")' "$STORY_JSON")
AC_BULLETS=$(jq -r '.acceptance_criteria | map("- " + .) | join("\n")' "$STORY_JSON")
REPOS=$(jq -r '.repos_affected[]' "$STORY_JSON")

PR_TITLE="feat(${STORY_ID}): ${STORY_TITLE}"
PR_BODY=$(cat <<EOF
**BMAD story:** ${FEATURE} / ${STORY_ID}
**FRs covered:** ${FRS}

## Acceptance Criteria
${AC_BULLETS}

---
*Created autonomously by the-oracle-story-dev skill (multi-gitter PR fan-out).*
EOF
)

: > "$OUT_FILE"

create_pr_for_repo() {
  local repo="$1"
  local dir="$WORKSPACE/$repo"
  [[ -d "$dir/.git" ]] || { echo "skip $repo: no checkout at $dir" >&2; return 0; }

  pushd "$dir" >/dev/null
  if ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    echo "skip $repo: branch $BRANCH not pushed" >&2
    popd >/dev/null
    return 0
  fi

  local existing
  existing=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url' 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    echo "$existing" >> "$OUT_FILE"
    echo "exists: $existing"
  else
    local url
    url=$(gh pr create --base "$BASE" --head "$BRANCH" \
            --title "$PR_TITLE" --body "$PR_BODY" 2>&1 | tail -1)
    if [[ "$url" =~ ^https:// ]]; then
      echo "$url" >> "$OUT_FILE"
      echo "created: $url"
    else
      echo "FAILED $repo: $url" >&2
    fi
  fi
  popd >/dev/null
}

if command -v multi-gitter >/dev/null 2>&1; then
  REPO_LIST=$(echo "$REPOS" | sed 's|^|carespace-ai/|' | paste -sd, -)
  TMP_SCRIPT=$(mktemp)
  cat > "$TMP_SCRIPT" <<'NOOP'
#!/usr/bin/env bash
# multi-gitter requires a working tree change to open a PR. We already pushed
# the branch out-of-band, so we just touch a tracking marker that gets ignored.
exit 0
NOOP
  chmod +x "$TMP_SCRIPT"

  if multi-gitter run "$TMP_SCRIPT" \
        --repo "$REPO_LIST" \
        --branch "$BRANCH" \
        --base-branch "$BASE" \
        --pr-title "$PR_TITLE" \
        --pr-body "$PR_BODY" \
        --commit-message "feat(${STORY_ID}): ${STORY_TITLE}" \
        --skip-pull-request=false 2>&1 | tee /tmp/multigitter.log; then
    grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' /tmp/multigitter.log >> "$OUT_FILE" || true
  else
    echo "multi-gitter failed; falling back to gh" >&2
    while read -r repo; do create_pr_for_repo "$repo"; done <<< "$REPOS"
  fi
  rm -f "$TMP_SCRIPT"
else
  echo "multi-gitter not installed; using gh per repo" >&2
  while read -r repo; do create_pr_for_repo "$repo"; done <<< "$REPOS"
fi

echo
echo "PR URLs written to $OUT_FILE:"
cat "$OUT_FILE"
