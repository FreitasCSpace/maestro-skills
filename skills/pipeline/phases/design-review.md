# Phase 4.5 — Design Review (UI changes only)

Skip if the changes are backend-only, config-only, or have no visual impact.
Run this phase if ANY `.tsx`, `.jsx`, `.css`, `.scss`, or `.module.css` files
were modified.

**Read the gstack design-review skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/design-review/SKILL.md
```

Focus on the diff — check spacing, alignment, hierarchy, color consistency,
and responsive behavior of the changed components.

If design issues found: fix them, commit. Max 2 fix iterations.

Append `## Design Review` to PIPELINE.md with findings.

```bash
git add -A && git commit -m "pipeline: design review fixes" && git push 2>/dev/null || true
git add -A PIPELINE.md && git commit -m "pipeline: design review" && git push
```
