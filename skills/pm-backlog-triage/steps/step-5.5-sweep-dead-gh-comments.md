# Step 5.5: Sweep Dead GitHub Bot Comments → /tmp/sweep-log.txt

For every repo in `$CI_REPOS`, fetches **all issue comments in one paginated call**
(`/repos/{repo}/issues/comments`), filters to those containing the bot marker
(`pm-bot:clickup-link v1`), extracts the ClickUp task ID from the URL, and verifies
the CU task still exists. If `GET task/{id}` returns 404 (task deleted), the
GitHub comment is **deleted**.

Idempotent — only touches comments whose linked CU task is actually gone.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/sweep-log.txt
DELETED=0; CHECKED=0; ALIVE=0; MAX=200

for repo in $CI_REPOS; do
  [ $CHECKED -ge $MAX ] && echo "HIT MAX $MAX checks" >> /tmp/sweep-log.txt && break

  # Pull all comments across all issues in this repo, one paginated call
  # Filter to bot-marker comments only, emit: comment_id<TAB>issue_url<TAB>body
  gh api --paginate "repos/$GITHUB_ORG/$repo/issues/comments?per_page=100" 2>/dev/null \
    | jq -r '
        .[]
        | select(.body | test("pm-bot:clickup-link v1"))
        | [(.id|tostring), .issue_url, .body] | @tsv
      ' > /tmp/sweep-candidates.tsv

  CANDIDATES=$(wc -l < /tmp/sweep-candidates.tsv)
  [ "$CANDIDATES" = "0" ] && continue
  echo "$repo: $CANDIDATES bot-comments to verify" >> /tmp/sweep-log.txt

  while IFS=$'\t' read -r comment_id issue_url body; do
    [ $CHECKED -ge $MAX ] && break
    CHECKED=$((CHECKED+1))

    # Extract CU task ID from URL pattern https://app.clickup.com/t/<id>
    CU_ID=$(echo "$body" | grep -oP 'app\.clickup\.com/t/\K[a-z0-9]+' | head -1)
    if [ -z "$CU_ID" ]; then
      echo "SKIP: $repo comment $comment_id — no CU URL in body" >> /tmp/sweep-log.txt
      continue
    fi

    # Verify CU task exists — 200 = alive, 404/error = dead
    STATUS=$(cu_api GET "task/$CU_ID" 2>/dev/null | jq -r '.id // "DEAD"')

    if [ "$STATUS" = "DEAD" ] || [ -z "$STATUS" ] || [ "$STATUS" = "null" ]; then
      # Delete the dead comment
      gh api -X DELETE "repos/$GITHUB_ORG/$repo/issues/comments/$comment_id" 2>/dev/null
      ISSUE_NUM=$(echo "$issue_url" | grep -oE '[0-9]+$')
      echo "DELETED: $repo#$ISSUE_NUM comment $comment_id → CU task $CU_ID is dead" \
        >> /tmp/sweep-log.txt
      DELETED=$((DELETED+1))
    else
      ALIVE=$((ALIVE+1))
    fi
    sleep 0.15
  done < /tmp/sweep-candidates.tsv
done

echo "=== Sweep Summary ===" >> /tmp/sweep-log.txt
echo "Checked: $CHECKED | Alive: $ALIVE | Deleted: $DELETED" >> /tmp/sweep-log.txt
tail -5 /tmp/sweep-log.txt
```
