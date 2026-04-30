# Phase 07 — Cumulative Scope Audit

Run after all stories complete, before opening PRs.

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"

  CHANGED=$(git diff --name-only origin/main..HEAD)

  # Union of every story's affected_modules + new_files_needed for this repo
  ALLOWED=$(grep -E "affected_modules|new_files_needed" \
    /tmp/oracle-work/PIPELINE.md | ... )  # derive from your PIPELINE.md log

  DEVIATIONS=$(comm -23 \
    <(echo "$CHANGED" | sort) \
    <(echo "$ALLOWED" | sort))

  if [ -n "$DEVIATIONS" ]; then
    echo "Scope deviations in $REPO:"
    echo "$DEVIATIONS"
    REPO_HAS_DEVIATION["$REPO"]=1
  fi

  cd /tmp/oracle-work
done
```

If `scope_deviations` is non-empty for any repo:
- That repo's PR gets the `scope-deviation` label (Phase 3).
- Deploy dispatch is **skipped** for the whole project (Phase 4).
- Post a comment on the anchor issue listing the deviating files.

Update PIPELINE.md with `## Scope Audit` section.

---

**Next:** Read `shards/phase-08-pr-group.md`
