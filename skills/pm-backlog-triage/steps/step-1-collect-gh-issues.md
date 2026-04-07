# Step 1: Collect GitHub Issues → /tmp/gh-issues.tsv

```bash
source ~/.claude/skills/_pm-shared/context.sh
gh auth status 2>&1 | head -1

> /tmp/gh-issues.tsv
for repo in $(gh repo list $GITHUB_ORG --limit 100 --json name --no-archived --jq '.[].name' 2>/dev/null); do
  DOMAIN=$(get_domain "$repo")
  gh issue list --repo $GITHUB_ORG/$repo --state open --json number,title,url,labels --limit 50 2>/dev/null \
    | jq -r --arg r "$repo" --arg d "$DOMAIN" '.[] | [$r, (.number|tostring), .title[0:80], .url, ((.labels[0].name) // "none"), $d] | @tsv' \
    >> /tmp/gh-issues.tsv 2>/dev/null
done

echo "=== GitHub Issues: $(wc -l < /tmp/gh-issues.tsv) total ==="
cut -f1 /tmp/gh-issues.tsv | sort | uniq -c | sort -rn | head -10
```
