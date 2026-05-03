# Phase 03 — BMAD Story Implementation Loop

For each story in BMAD order (from stories-index.md in context), run three
`claude --print` subprocesses: create-story → dev-story → code-review.
Commit after each story. Comment on anchor issue after each epic.

```bash
STORIES_DIR=/tmp/oracle-work/stories
PLANNING_DIR=/tmp/oracle-work/backlog/bmad-context/$PROJECT_SLUG
HARD_FAILURES=0
RESUME_ANNOUNCED=false
LAST_EPIC=0
EPIC_STORY_COUNT=0
```

## Resume discovery

Before iterating stories, identify where the previous run stopped.
This is done by scanning `stories-order.txt` (written by phase-01) and finding
the first story key NOT present in `COMPLETED_STORIES`.

```bash
if [ ${#COMPLETED_STORIES[@]} -gt 0 ]; then
  echo ""
  echo "=== RESUME MODE: ${#COMPLETED_STORIES[@]} stories already committed ==="
  echo "Completed: ${COMPLETED_STORIES[*]}"
  echo "Will skip completed stories and resume from the first uncommitted one."
  echo ""
fi
```

Iterate `/tmp/oracle-work/stories-order.txt` via bash `while read`. Each line is
tab-separated `EPIC_NUM`, `STORY_NUM`, `STORY_TITLE`. `STORY_KEY` is computed by
bash (same formula as commit subjects). Per-story metadata is sourced from
`story-meta/N-M.sh` written by phase-01's extract-stories.py.

```bash
while IFS=$'\t' read -r EPIC_NUM STORY_NUM STORY_TITLE; do
  [ -z "$STORY_NUM" ] && continue

  STORY_KEY="${EPIC_NUM}-${STORY_NUM}-$(echo "$STORY_TITLE" \
    | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-50)"

  STORY_AFFECTED_MODULES="" STORY_AC=""
  STORY_META="/tmp/oracle-work/story-meta/${EPIC_NUM}-${STORY_NUM}.sh"
  [ -f "$STORY_META" ] && source "$STORY_META"

  # Epic transition gate — post completion comment when epic number changes
  if [ "$EPIC_NUM" != "$LAST_EPIC" ] && [ "$LAST_EPIC" -gt 0 ]; then
    gh issue comment "$ANCHOR" \
      --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "✅ Epic $LAST_EPIC complete — $EPIC_STORY_COUNT stories implemented."
    EPIC_STORY_COUNT=0
  fi
  LAST_EPIC="$EPIC_NUM"
```

### Step A — Skip if already committed

```bash
  if [[ " ${COMPLETED_STORIES[*]} " =~ " ${STORY_KEY} " ]]; then
  echo "### Story $STORY_KEY — SKIPPED (already committed in prior run)"
  echo "### Story $STORY_KEY — COMPLETE" >> /tmp/oracle-work/PIPELINE.md
  continue
fi

# First un-skipped story — announce the resume point
if [ "$RESUME_ANNOUNCED" = "false" ] && [ ${#COMPLETED_STORIES[@]} -gt 0 ]; then
  RESUME_ANNOUNCED=true
  echo ""
  echo "=== RESUMING from Epic $EPIC_NUM, Story $EPIC_NUM.$STORY_NUM — $STORY_TITLE ==="
  gh issue comment "$ANCHOR" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Pipeline resuming from **Epic $EPIC_NUM, Story $EPIC_NUM.$STORY_NUM** — \`$STORY_TITLE\` (${#COMPLETED_STORIES[@]} stories already committed from prior run)."
  echo ""
fi
```

### Step B — Create story file

```bash
STORY_FILE="$STORIES_DIR/${STORY_KEY}.md"

CREATE_OUT=$(claude --print \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
  --model claude-sonnet-4-6 \
  "PROJECT_ROOT: /tmp/oracle-work
PLANNING_DIR: $PLANNING_DIR
implementation_artifacts: $STORIES_DIR
project-root: /tmp/oracle-work

$(cat "$WF_CREATE_STORY")

Target story: $STORY_KEY
Story title: $STORY_TITLE
Affected modules: $STORY_AFFECTED_MODULES
Acceptance criteria: $STORY_AC

AUTONOMOUS MODE: Create story file at $STORY_FILE. No pauses.
Last line JSON: {\"status\":\"done\",\"story_file\":\"$STORY_FILE\"}" 2>&1)

echo "$CREATE_OUT" | tail -3
```

### Step B — Implement story

```bash
PRIMARY_REPO=$(echo "$STORY_AFFECTED_MODULES" | grep -oE 'carespace-[a-z]+' | head -1)
PRIMARY_REPO="${PRIMARY_REPO:-${INVOLVED_REPOS[0]}}"
REPO_ROOT="/tmp/oracle-work/workspace/$PRIMARY_REPO"

MCP_CONFIG="$REPO_ROOT/.mcp.json"
[ -f "$MCP_CONFIG" ] || { echo "BLOCKED: .mcp.json missing for $PRIMARY_REPO — phase-02 must have failed"; exit 1; }

DEV_OUT=$(claude --print \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep,mcp__serena__*,mcp__code-graph__*" \
  --model claude-sonnet-4-6 \
  --max-turns 50 \
  $MCP_FLAG \
  "PROJECT_ROOT: $REPO_ROOT
PLANNING_DIR: $PLANNING_DIR
implementation_artifacts: $STORIES_DIR
project-root: $REPO_ROOT
ALL_REPO_ROOTS: $(for r in "${INVOLVED_REPOS[@]}"; do echo "/tmp/oracle-work/workspace/$r"; done | tr '\n' ' ')

## Codebase Navigation (use these BEFORE reaching for Read)
- mcp__serena__find_symbol — look up any function/class/variable by name
- mcp__serena__get_file_outline — get all symbols in a file without reading it
- mcp__serena__find_references — find all call sites of a symbol
- mcp__code-graph__semantic_search — find relevant code by description
- Only use Read with offset+limit (50-100 lines) when you need the exact implementation body

$(cat "$WF_DEV_STORY")

Story file: $STORY_FILE
AUTONOMOUS MODE: Implement all tasks. Run tests after each task. No pauses.
Scope: touch only files in — $STORY_AFFECTED_MODULES
Last line JSON: {\"status\":\"review|halted\",\"tasks_done\":0,\"halt_reason\":\"\"}" 2>&1)

DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null)

if [ "$DEV_STATUS" = "halted" ]; then
  HALT_REASON=$(echo "$DEV_OUT" | tail -1 | jq -r '.halt_reason')
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Story \`$STORY_KEY\` halted: $HALT_REASON — retrying once"

  DEV_OUT=$(claude --print \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep,mcp__serena__*,mcp__code-graph__*" \
    --model claude-sonnet-4-6 \
    --max-turns 50 \
    --mcp-config "$MCP_CONFIG" \
    "PROJECT_ROOT: $REPO_ROOT
$(cat "$WF_DEV_STORY")
Story file: $STORY_FILE
Previous halt reason: $HALT_REASON — resolve it and complete implementation.
Last line JSON: {\"status\":\"review|halted\",\"tasks_done\":0,\"halt_reason\":\"\"}" 2>&1)
  DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null)
fi

if [ "$DEV_STATUS" = "halted" ]; then
  HARD_FAILURES=$((HARD_FAILURES + 1))
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "❌ Story \`$STORY_KEY\` failed after retry ($HARD_FAILURES total failures)."
  echo "### Story $STORY_KEY — FAILED" >> /tmp/oracle-work/PIPELINE.md
  [ $HARD_FAILURES -ge 5 ] && {
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "PIPELINE_RUNAWAY: 5 hard failures — aborting pipeline"
    gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --remove-label maestro:implementing --add-label maestro:blocked
    exit 2
  }
  continue
fi
```

### Step C — Code review

```bash
REVIEW_OUT=$(claude --print \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
  --model claude-sonnet-4-6 \
  "PROJECT_ROOT: $REPO_ROOT
PLANNING_DIR: $PLANNING_DIR

$(cat "$WF_CODE_REVIEW")

Story file: $STORY_FILE
Last line JSON: {\"status\":\"approved|changes_requested\",\"findings_high\":0}" 2>&1)

REVIEW_STATUS=$(echo "$REVIEW_OUT" | tail -1 | jq -r '.status' 2>/dev/null)

if [ "$REVIEW_STATUS" = "changes_requested" ]; then
  claude --print \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
    --model claude-sonnet-4-6 \
    --max-turns 20 \
    "PROJECT_ROOT: $REPO_ROOT
$(cat "$WF_DEV_STORY")
Story file: $STORY_FILE
Address all code review findings. High severity first.
Last line JSON: {\"status\":\"done\"}" 2>&1
fi
```

### Step D — Atomic commit per repo

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "/tmp/oracle-work/workspace/$REPO"
  if ! git diff --quiet HEAD 2>/dev/null || git status --porcelain | grep -q .; then
    git add -A
    git commit -m "[Story $STORY_KEY] $STORY_TITLE"
    echo "Committed in $REPO"
  fi
  cd /tmp/oracle-work
done

echo "### Story $STORY_KEY — COMPLETE" >> /tmp/oracle-work/PIPELINE.md
EPIC_STORY_COUNT=$((EPIC_STORY_COUNT + 1))

done < "/tmp/oracle-work/stories-order.txt"
```

### Step E — Final epic gate

After the while loop exits, post the completion comment for the last epic:

```bash
[ "$LAST_EPIC" -gt 0 ] && \
  gh issue comment "$ANCHOR" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "✅ Epic $LAST_EPIC complete — $EPIC_STORY_COUNT stories implemented."
```

---

**After last story:** Read `shards/phase-04-pr-group.md`
