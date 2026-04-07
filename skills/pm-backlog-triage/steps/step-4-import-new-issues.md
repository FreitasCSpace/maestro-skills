# Step 4: Import New Issues → /tmp/import-log.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/new-issues.tsv
> /tmp/import-log.txt
IMPORTED=0; SKIPPED=0; MAX=50

while IFS=$'\t' read -r repo num title url label domain; do
  if grep -qF "$url" /tmp/cu-urls.txt 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
  else
    echo -e "$repo\t$num\t$title\t$url\t$label\t$domain" >> /tmp/new-issues.tsv
  fi
done < /tmp/gh-issues.tsv

NEW=$(wc -l < /tmp/new-issues.tsv)
echo "New: $NEW | Skipped (dedup): $SKIPPED" | tee /tmp/import-log.txt

COUNT=0
while IFS=$'\t' read -r repo num title url label domain; do
  [ $COUNT -ge $MAX ] && echo "HIT MAX $MAX — stopping" >> /tmp/import-log.txt && break

  # Priority: security/compliance=1 (urgent), bug=2 (high), enhancement/feature=3, other=4
  case "$label" in
    security|compliance) PRI=1;;
    bug) PRI=2;;
    enhancement|feature) PRI=3;;
    *) PRI=4;;
  esac

  # SP estimation from context.py heuristics
  case "$label" in
    security) SP=8;;
    bug)
      case "$PRI" in 1) SP=8;; 2) SP=5;; *) SP=2;; esac;;
    feature|enhancement)
      echo "$title" | grep -qiE "refactor|rewrite|migrate|redesign" && SP=21 || SP=5;;
    *) SP=2;;
  esac

  # Domain lead for auto-assignment
  LEAD="${DOMAIN_LEAD[$domain]:-}"

  # Type prefix from label (BUG/FEATURE/TASK/SECURITY) — drives Step 6 SP estimation
  case "$label" in
    bug)                 TYPE="BUG";      TYPE_TAG="bug" ;;
    feature|enhancement) TYPE="FEATURE";  TYPE_TAG="feature" ;;
    security|compliance) TYPE="SECURITY"; TYPE_TAG="security" ;;
    *)                   TYPE="TASK";     TYPE_TAG="task" ;;
  esac

  # Strip any existing "Bug:"/"Feature:"/"Task:" prefix from title to avoid double-tagging
  CLEAN_TITLE=$(echo "$title" | sed -E 's/^(Bug|Feature|Feat|Task|Security|Chore):[[:space:]]*//i')

  PAYLOAD=$(jq -n \
    --arg n "[$TYPE] $CLEAN_TITLE" \
    --arg d "GitHub: $url\nRepo: $repo\nDomain: $domain\nLabel: $label" \
    --argjson p $PRI \
    --arg tag1 "pm-bot-imported" \
    --arg tag2 "$domain" \
    --arg tag3 "$TYPE_TAG" \
    '{name:$n, description:$d, priority:$p, tags:[$tag1,$tag2,$tag3]}')

  RES=$(cu_api POST "list/$LIST_MASTER_BACKLOG/task" "$PAYLOAD" | jq -r '.id // "ERROR"')

  # Set SP via custom field, assign lead, post bot comment on GH issue
  CMT="skipped"
  if [ "$RES" != "ERROR" ] && [ -n "$RES" ]; then
    cu_api POST "task/$RES/field/$SP_FIELD_ID" "{\"value\":$SP}" > /dev/null

    if [ -n "$LEAD" ]; then
      ASSIGN_PAYLOAD=$(jq -n --argjson uid "$LEAD" '{assignees:{add:[$uid]}}')
      cu_api PUT "task/$RES" "$ASSIGN_PAYLOAD" > /dev/null
    fi

    # Post the canonical bot comment on the GH issue (rich format)
    CU_URL="https://app.clickup.com/t/$RES"
    CMT=$(gh_upsert_clickup_comment "$GITHUB_ORG/$repo" "$num" "$CU_URL" "$PRI" "$SP" "$domain")
    # Track the new pair for downstream backfill (skips it in Step 5 — already handled)
    printf '%s\t%s/%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$RES" "$GITHUB_ORG" "$repo" "$num" "$CU_URL" "$PRI" "$SP" "$domain" \
      >> /tmp/cu-gh-map.tsv
  fi

  echo "IMPORT $repo#$num → $RES (pri=$PRI, sp=$SP, domain=$domain, gh-comment=$CMT)" >> /tmp/import-log.txt
  COUNT=$((COUNT+1)); IMPORTED=$((IMPORTED+1)); sleep 0.3
done < /tmp/new-issues.tsv

echo "Imported: $IMPORTED" >> /tmp/import-log.txt
cat /tmp/import-log.txt
```
