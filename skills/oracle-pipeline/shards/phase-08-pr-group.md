# Phase 08 — Multi-Repo PR Group

Push and open one PR per repo, all targeting `main`. PRs are linked by
`group:project-<slug>` label.

> This loop is hand-rolled because Oracle stories produce *different* diffs per
> repo. For lifecycle ops (group merge / close / status after approval), see the
> sibling skill `oracle-pipeline-lifecycle/` which wraps multi-gitter.

```bash
PR_TITLE="[Oracle Project: $PROJECT_SLUG] $PROJECT_NAME"
declare -A PR_URLS PR_SHAS

for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  git push --force-with-lease -u origin "$BRANCH"

  LABELS="oracle-project,group:project-$PROJECT_SLUG,$PROJECT_LABEL"
  [ "${REPO_HAS_DEVIATION[$REPO]}" = "1" ] && LABELS="$LABELS,scope-deviation"

  PR_BODY="Implements Oracle project \`$PROJECT_SLUG\` stories.\n\n\
Anchor issue: $TARGET_ORG/the-oracle-backlog#$ANCHOR_ISSUE\n\
Stories: $(jq -r '.[].number' /tmp/oracle-work/stories.json | tr '\n' ' ')\n\n\
**Do not merge until all PRs in group are approved.**"

  EXISTING=$(gh pr list --repo "$TARGET_ORG/$REPO" \
    --head "$BRANCH" --state open --json number,url | jq '.[0]')

  if [ "$EXISTING" != "null" ]; then
    PR_NUM=$(echo "$EXISTING" | jq -r .number)
    gh pr edit "$PR_NUM" \
      --repo "$TARGET_ORG/$REPO" \
      --title "$PR_TITLE" --body "$PR_BODY" --add-label "$LABELS"
    PR_URL=$(echo "$EXISTING" | jq -r .url)
  else
    PR_URL=$(gh pr create \
      --repo "$TARGET_ORG/$REPO" \
      --base main --head "$BRANCH" \
      --title "$PR_TITLE" --body "$PR_BODY" \
      --label "$LABELS")
  fi

  PR_URLS["$REPO"]="$PR_URL"
  PR_SHAS["$REPO"]="$(git rev-parse HEAD)"
  cd /tmp/oracle-work
done

gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Pipeline complete — PRs opened:
$(for r in "${!PR_URLS[@]}"; do echo "- $r: ${PR_URLS[$r]}"; done)"
```

---

**Next:** Read `shards/phase-09-deploy.md`
