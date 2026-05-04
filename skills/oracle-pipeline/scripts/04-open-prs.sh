#!/usr/bin/env bash
# Phase 04 — Push branches and open PR group; flip anchor label to deploying.
set -euo pipefail

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
. /tmp/oracle-work/env.02.sh

cd /tmp/oracle-work
PR_TITLE="[Oracle Project: $PROJECT_SLUG] $PROJECT_NAME"
declare -A PR_URLS

for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  if ! git diff --quiet origin/main..HEAD 2>/dev/null; then
    git push --force-with-lease -u origin "$BRANCH"

    PR_BODY="Implements Oracle project \`$PROJECT_SLUG\`.

Tracking issue: $TARGET_ORG/the-oracle-backlog#$ANCHOR

**Do not merge until all PRs in this group are approved.**"
    LABELS="oracle-project,group:project-$PROJECT_SLUG,$PROJECT_LABEL"

    EXISTING=$(gh pr list --repo "$TARGET_ORG/$REPO" \
      --head "$BRANCH" --state open --json number,url | jq '.[0]')

    if [ "$EXISTING" != "null" ] && [ -n "$EXISTING" ]; then
      PR_NUM=$(echo "$EXISTING" | jq -r .number)
      gh pr edit "$PR_NUM" --repo "$TARGET_ORG/$REPO" \
        --title "$PR_TITLE" --body "$PR_BODY" --add-label "$LABELS"
      PR_URL=$(echo "$EXISTING" | jq -r .url)
    else
      PR_URL=$(gh pr create --repo "$TARGET_ORG/$REPO" \
        --base main --head "$BRANCH" \
        --title "$PR_TITLE" --body "$PR_BODY" \
        --label "$LABELS")
    fi

    PR_URLS["$REPO"]="$PR_URL"
    echo "PR for $REPO: $PR_URL"
  else
    echo "No changes in $REPO — skipping PR"
  fi
  cd /tmp/oracle-work
done

# Comment on anchor with PR list
PR_LIST=""
for REPO in "${!PR_URLS[@]}"; do
  PR_LIST="$PR_LIST"$'\n'"- $REPO: ${PR_URLS[$REPO]}"
done
gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "$(printf 'Pipeline complete for `%s`.\n\nPRs opened:%s' "$PROJECT_SLUG" "$PR_LIST")"

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

# Persist PR URLs for phase 05
declare -p PR_URLS > /tmp/oracle-work/env.04.sh
echo "Env written: /tmp/oracle-work/env.04.sh"
