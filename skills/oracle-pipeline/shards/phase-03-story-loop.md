# Phase 03 — BMAD Story Implementation Loop

For each story in BMAD order (from stories-index.md in context), run three
`claude --print` subprocesses: create-story → dev-story → code-review.
Commit after each story. Comment on anchor issue after each epic.

```
STORIES_DIR=/tmp/oracle-work/stories
HARD_FAILURES=0

for STORY in <ordered list from stories-index.md>:
```

### Step A — Create story file

```bash
STORY_KEY="${EPIC_NUM}-${STORY_NUM}-$(echo "$STORY_TITLE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 40)"
STORY_FILE="$STORIES_DIR/${STORY_KEY}.md"

CREATE_OUT=$(claude --print \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
  --model claude-sonnet-4-6 \
  "PROJECT_ROOT: /tmp/oracle-work
PLANNING_DIR: /tmp/oracle-work/backlog/bmad-context/$PROJECT_SLUG
implementation_artifacts: $STORIES_DIR
project-root: /tmp/oracle-work/workspace

$(cat "$WF_CREATE_STORY")

Target story: $STORY_KEY
Story title: $STORY_TITLE
Affected modules: $STORY_AFFECTED_MODULES
Acceptance criteria: $STORY_AC

AUTONOMOUS MODE: Create the story file at $STORY_FILE. No pauses.
Last line JSON: {\"status\":\"done\",\"story_file\":\"$STORY_FILE\"}" 2>&1)

echo "$CREATE_OUT" | tail -5
```

### Step B — Implement story

```bash
DEV_OUT=$(claude --print \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
  --model claude-sonnet-4-6 \
  --max-turns 50 \
  "PROJECT_ROOT: /tmp/oracle-work/workspace
implementation_artifacts: $STORIES_DIR
project-root: /tmp/oracle-work/workspace
INVOLVED_REPOS: ${INVOLVED_REPOS[*]}

$(cat "$WF_DEV_STORY")

Story file: $STORY_FILE
AUTONOMOUS MODE: Implement all tasks. No pauses. Run tests after each task.
Scope: touch only files in affected_modules — ${STORY_AFFECTED_MODULES}.
Last line JSON: {\"status\":\"review|halted\",\"tasks_done\":0,\"halt_reason\":\"\"}" 2>&1)

DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null)

if [ "$DEV_STATUS" = "halted" ]; then
  HALT_REASON=$(echo "$DEV_OUT" | tail -1 | jq -r '.halt_reason')
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Story $STORY_KEY halted: $HALT_REASON — retrying once"
  # Retry once
  DEV_OUT=$(claude --print \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
    --model claude-sonnet-4-6 \
    --max-turns 50 \
    "$(cat "$WF_DEV_STORY")
Story file: $STORY_FILE
Previous halt: $HALT_REASON
Resolve the halt and complete implementation.
Last line JSON: {\"status\":\"review|halted\",\"tasks_done\":0,\"halt_reason\":\"\"}" 2>&1)
  DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null)
fi

if [ "$DEV_STATUS" = "halted" ]; then
  HARD_FAILURES=$((HARD_FAILURES + 1))
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "❌ Story $STORY_KEY failed after retry. Pipeline continuing with next story."
  echo "### Story $STORY_KEY — FAILED" >> /tmp/oracle-work/PIPELINE.md
  [ $HARD_FAILURES -ge 5 ] && {
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "PIPELINE_RUNAWAY: 5 hard failures — aborting"
    gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --remove-label oracle:implementing --add-label oracle:blocked-pipeline-failed
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
  "PROJECT_ROOT: /tmp/oracle-work/workspace

$(cat "$WF_CODE_REVIEW")

Story file: $STORY_FILE
Review the implementation for story $STORY_KEY.
Last line JSON: {\"status\":\"approved|changes_requested\",\"findings_high\":0}" 2>&1)

REVIEW_STATUS=$(echo "$REVIEW_OUT" | tail -1 | jq -r '.status' 2>/dev/null)

# One fix cycle if changes requested
if [ "$REVIEW_STATUS" = "changes_requested" ]; then
  FINDINGS=$(echo "$REVIEW_OUT" | tail -1 | jq -r '.findings_high')
  claude --print \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
    --model claude-sonnet-4-6 \
    --max-turns 20 \
    "$(cat "$WF_DEV_STORY")
Story file: $STORY_FILE
Address all code review findings. High severity first.
Last line JSON: {\"status\":\"done\"}" 2>&1
fi
```

### Step D — Atomic commit per repo

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "/tmp/oracle-work/workspace/$REPO"
  if ! git diff --quiet HEAD; then
    git add -A
    git commit -m "[Story $STORY_KEY] $STORY_TITLE"
  fi
  cd /tmp/oracle-work
done

echo "### Story $STORY_KEY — COMPLETE" >> /tmp/oracle-work/PIPELINE.md
```

### Step E — Epic gate (after last story in each epic)

```bash
# After all stories in epic N are done:
gh issue comment "$ANCHOR" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "✅ Epic $EPIC_NUM complete — $EPIC_STORY_COUNT stories implemented."
```

---

**After last story:** Read `shards/phase-04-pr-group.md`
