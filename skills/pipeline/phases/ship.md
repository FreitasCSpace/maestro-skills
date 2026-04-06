# Phase 8 — Ship

**Read the gstack ship skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/ship/SKILL.md
```

## Create PR

```bash
BASE=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
gh pr create \
  --base "$BASE" \
  --title "$(sed -n '/^## Task/,/^## /p' PIPELINE.md | head -n -1 | tail -n +2 | head -1 | cut -c1-70)" \
  --body "$(cat PIPELINE.md)

---
*Created autonomously by the Maestro pipeline.*"
```

Update PIPELINE.md `## Status` to `COMPLETE`. Add `## Ship` with PR URL.

```bash
git add PIPELINE.md && git commit -m "pipeline: shipped" && git push
```
