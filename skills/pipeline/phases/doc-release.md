# Phase 9 — Document Release

**Read the gstack document-release skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/document-release/SKILL.md
```

Update any project documentation affected by the changes:

- README.md — if new features, commands, or setup steps were added
- ARCHITECTURE.md — if structural changes were made
- CLAUDE.md — if new commands, conventions, or patterns were introduced

Only update docs that are actually affected. Do not touch accurate docs.

Append `## Documentation` to PIPELINE.md listing what was updated.

```bash
git add -A && git commit -m "pipeline: update documentation" && git push
```
