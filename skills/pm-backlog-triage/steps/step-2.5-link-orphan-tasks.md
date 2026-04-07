# Step 2.5: Fuzzy-Link Orphan CU Tasks → /tmp/orphan-link-log.txt

For every CU backlog task that has **no GitHub URL** in its description, search GitHub
issues across `$CI_REPOS` by title. If a high-confidence match is found (≥0.85 similarity
via Python `difflib`), append the URL to the CU task description and add it to
`/tmp/cu-urls.txt` so downstream steps treat it as already linked.

```bash
source ~/.claude/skills/_pm-shared/context.sh
> /tmp/orphan-link-log.txt
LINKED=0; SCANNED=0; SKIPPED=0; MAX=50

# Extract orphan tasks: id<TAB>name (no github.com URL in desc)
jq -r '.[] | select((.desc | test("https://github\\.com/[^/]+/[^/]+/issues/[0-9]+")) | not)
            | [.id, .name] | @tsv' \
  /tmp/cu-backlog.json > /tmp/cu-orphans.tsv
ORPHAN_COUNT=$(wc -l < /tmp/cu-orphans.tsv)
echo "Orphan CU tasks (no GH URL): $ORPHAN_COUNT"

# Build a single GH search corpus once: all open issues across CI_REPOS
# Format: repo<TAB>num<TAB>url<TAB>title_lower
> /tmp/gh-search-corpus.tsv
for repo in $CI_REPOS; do
  gh issue list --repo "$GITHUB_ORG/$repo" --state all --json number,title,url --limit 200 2>/dev/null \
    | jq -r --arg r "$repo" '.[] | [$r, (.number|tostring), .url, (.title | ascii_downcase)] | @tsv' \
    >> /tmp/gh-search-corpus.tsv
done
echo "GH issues in search corpus: $(wc -l < /tmp/gh-search-corpus.tsv)"

# Fuzzy match using Python difflib (no extra deps)
while IFS=$'\t' read -r cu_id cu_name; do
  [ $SCANNED -ge $MAX ] && echo "HIT MAX $MAX scans" >> /tmp/orphan-link-log.txt && break
  SCANNED=$((SCANNED+1))

  # Strip [TAG] prefix for cleaner matching
  CLEAN_NAME=$(echo "$cu_name" | sed -E 's/^\[[A-Z]+\][[:space:]]*//' | tr '[:upper:]' '[:lower:]')

  MATCH=$(python3 - <<PYEOF
import sys
from difflib import SequenceMatcher
target = """$CLEAN_NAME"""
best_ratio = 0.0
best_line = None
with open("/tmp/gh-search-corpus.tsv") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4: continue
        repo, num, url, title = parts
        r = SequenceMatcher(None, target, title).ratio()
        if r > best_ratio:
            best_ratio = r; best_line = (repo, num, url, r)
if best_line and best_line[3] >= 0.85:
    print(f"{best_line[0]}\t{best_line[1]}\t{best_line[2]}\t{best_line[3]:.2f}")
PYEOF
)

  if [ -z "$MATCH" ]; then
    echo "NO MATCH: $cu_name" >> /tmp/orphan-link-log.txt
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  REPO=$(echo "$MATCH" | cut -f1)
  NUM=$(echo "$MATCH"  | cut -f2)
  URL=$(echo "$MATCH"  | cut -f3)
  CONF=$(echo "$MATCH" | cut -f4)

  # Append URL to CU task description (preserve existing desc)
  EXISTING_DESC=$(jq -r --arg id "$cu_id" '.[] | select(.id==$id) | .desc' /tmp/cu-backlog.json)
  NEW_DESC="${EXISTING_DESC}

GitHub: $URL
_Auto-linked by pm-backlog-triage (confidence: $CONF)_"

  PAYLOAD=$(jq -n --arg d "$NEW_DESC" '{description:$d}')
  RES=$(cu_api PUT "task/$cu_id" "$PAYLOAD" | jq -r '.id // "ERROR"')

  if [ "$RES" != "ERROR" ]; then
    echo "LINKED: $cu_name → $REPO#$NUM (conf=$CONF)" >> /tmp/orphan-link-log.txt
    echo "$URL" >> /tmp/cu-urls.txt
    LINKED=$((LINKED+1))
  else
    echo "ERROR: $cu_name → could not update CU task" >> /tmp/orphan-link-log.txt
  fi
  sleep 0.2
done < /tmp/cu-orphans.tsv

# Re-sort cu-urls.txt for downstream dedup
sort -u /tmp/cu-urls.txt -o /tmp/cu-urls.txt

echo "=== Orphan Link Summary ===" >> /tmp/orphan-link-log.txt
echo "Scanned: $SCANNED | Linked: $LINKED | No match: $SKIPPED" >> /tmp/orphan-link-log.txt
tail -3 /tmp/orphan-link-log.txt
```
