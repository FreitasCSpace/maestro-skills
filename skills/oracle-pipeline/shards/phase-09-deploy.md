# Phase 09 — Trigger Ephemeral Deploy

Only dispatch if `scope_deviations` is empty across ALL repos.

```bash
if [ "${#SCOPE_DEVIATION_REPOS[@]}" -eq 0 ]; then
  INVOLVED_REPOS_JSON=$(printf '%s\n' "${INVOLVED_REPOS[@]}" | jq -R . | jq -s .)
  PR_SHAS_JSON=$(for r in "${!PR_SHAS[@]}"; do
    echo "{\"repo\":\"$r\",\"sha\":\"${PR_SHAS[$r]}\"}"; done | jq -s .)

  gh api "repos/$TARGET_ORG/infra/dispatches" \
    --method POST \
    --field event_type='oracle.project.complete' \
    --field "client_payload[project_slug]=$PROJECT_SLUG" \
    --field "client_payload[anchor_issue_number]=$ANCHOR_ISSUE" \
    --field "client_payload[involved_repos]=$INVOLVED_REPOS_JSON" \
    --field "client_payload[git_sha_per_repo]=$PR_SHAS_JSON" \
    --field "client_payload[bmad_context_path]=bmad-context/$PROJECT_SLUG"

  # Move group from implementing → deploying
  jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
    gh issue edit "$n" \
      --repo "$TARGET_ORG/the-oracle-backlog" \
      --remove-label oracle:implementing \
      --add-label oracle:deploying
  done

  DEPLOY_DISPATCHED=true
else
  gh issue comment "$ANCHOR_ISSUE" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Deploy skipped — scope deviations in: ${SCOPE_DEVIATION_REPOS[*]}"
  DEPLOY_DISPATCHED=false
fi
```

---

**Next:** Read `shards/phase-10-output.md`
