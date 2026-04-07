# Step 3: Load Vault Index → /tmp/vault-existing.txt

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Paginate vault contents (handles >1000 files)
> /tmp/vault-existing.txt
PAGE=1
while true; do
  RESULT=$(gh api "repos/$HUDDLE_VAULT_REPO/contents/$HUDDLE_VAULT_PATH?per_page=100&page=$PAGE" \
    --jq '.[].name' 2>/dev/null)
  [ -z "$RESULT" ] && break
  echo "$RESULT" >> /tmp/vault-existing.txt
  COUNT=$(echo "$RESULT" | wc -l)
  [ "$COUNT" -lt 100 ] && break
  PAGE=$((PAGE+1))
done

echo "Existing vault files: $(wc -l < /tmp/vault-existing.txt)"
```
