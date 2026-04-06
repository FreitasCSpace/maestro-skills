# Phase 4 — Build

Implement the changes.

**SCOPE DISCIPLINE:** Only modify files listed in PIPELINE.md `## Relevant Files`.
If you need to change additional files, add them to the list first.

1. Read PIPELINE.md for context (task, investigation, plan, relevant files)
2. Read ONLY the relevant files identified during reconnaissance
3. Make the minimal, correct changes needed
4. Follow existing code patterns (check neighboring files for style)
5. Write tests if the project has a test framework

**For large repos:** Use the Agent tool with `subagent_type="Explore"` to
search for patterns and imports without bloating your main context.

## Safe Editing Strategy (CRITICAL for large files)

The Edit tool can fail and loop when `old_string` isn't unique in a large file.

**Before editing ANY file, check its size:**
```bash
wc -l path/to/file.tsx
```

**Choose your approach based on file size:**

1. **Small files (< 200 lines):** Edit tool works normally.

2. **Medium files (200-500 lines):** Use Edit with 5-10 lines of context
   in `old_string`. If it fails with "not unique", switch to approach 3.

3. **Large files (500+ lines):** Do NOT use Edit. Instead:
   - **Write tool** — read full file, modify in memory, write entire file
   - **New file** — create a new file and import it
   - **sed via Bash** — `grep -n` to find line, `sed -i` to change it

**NEVER retry a failed Edit more than once.** Switch to Write or sed immediately.

**Prefer creating new files** over modifying large existing ones.

## Run tests

```bash
if [ -f "package.json" ]; then
  npm test 2>&1 | tail -30
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  ./gradlew test 2>&1 | tail -30
elif [ -f "go.mod" ]; then
  go test ./... 2>&1 | tail -30
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  pytest 2>&1 | tail -30
elif [ -f "pubspec.yaml" ]; then
  flutter test 2>&1 | tail -30
else
  echo "No test runner detected"
fi
```

## Commit

```bash
git add -A && git commit -m "pipeline: implement changes" && git push
```

Append `## Build` to PIPELINE.md with files changed and test results.

## Update codebase map

```bash
cat >> .pipeline/CODEBASE_MAP.md << UPDATEEOF

## Update ($(date +%Y-%m-%d)) — Issue #${ISSUE_NUM}
### Files Modified
$(git diff --name-only HEAD~1)
UPDATEEOF
git add .pipeline/CODEBASE_MAP.md && git commit -m "pipeline: update codebase map" && git push
```
