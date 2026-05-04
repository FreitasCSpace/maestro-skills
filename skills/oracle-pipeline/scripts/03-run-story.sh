#!/usr/bin/env bash
# Phase 03 — Run ONE story end-to-end with developer-skill quality gates.
#
# Lifecycle (BMAD developer pattern):
#   1. bmad-create-story  → story file
#   2. bmad-dev-story     → implementation
#   3. lint + test + coverage gates (retry dev-story once on gate fail)
#   4. bmad-code-review   → self-review (re-run dev if changes_requested)
#   5. atomic commit per repo
#
# Args:
#   $1 = EPIC_NUM
#   $2 = STORY_NUM
#   $3 = STORY_TITLE
#
# Exit codes: 0=committed, 1=halted (caller increments HARD_FAILURES), 2=skipped
set -euo pipefail

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
. /tmp/oracle-work/env.02.sh

EPIC_NUM="$1"; STORY_NUM="$2"; STORY_TITLE="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STORY_KEY="${EPIC_NUM}-${STORY_NUM}-$(echo "$STORY_TITLE" \
  | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-50)"

# Skip if already committed
for s in "${COMPLETED_STORIES[@]:-}"; do
  if [ "$s" = "$STORY_KEY" ]; then
    echo "### Story $STORY_KEY — SKIPPED (already committed)"
    echo "### Story $STORY_KEY — COMPLETE" >> /tmp/oracle-work/PIPELINE.md
    exit 2
  fi
done

# Load per-story metadata
STORY_AFFECTED_MODULES="" STORY_AC=""
META="/tmp/oracle-work/story-meta/${EPIC_NUM}-${STORY_NUM}.sh"
[ -f "$META" ] && . "$META"

STORIES_DIR=/tmp/oracle-work/stories
STORY_FILE="$STORIES_DIR/${STORY_KEY}.md"

PRIMARY_REPO=$(echo "$STORY_AFFECTED_MODULES" | grep -oE 'carespace-[a-z]+' | head -1 || true)
PRIMARY_REPO="${PRIMARY_REPO:-${INVOLVED_REPOS[0]}}"
REPO_ROOT="/tmp/oracle-work/workspace/$PRIMARY_REPO"
MCP_CONFIG="$REPO_ROOT/.mcp.json"
[ -f "$MCP_CONFIG" ] || { echo "BLOCKED: .mcp.json missing for $PRIMARY_REPO"; exit 1; }

echo ""
echo "=== Story $STORY_KEY — $STORY_TITLE (repo: $PRIMARY_REPO) ==="

# ── Step 1: bmad-create-story ────────────────────────────────────────────────
claude --print \
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
Last line JSON: {\"status\":\"done\",\"story_file\":\"$STORY_FILE\"}" 2>&1 | tail -3

# ── Step 2: bmad-dev-story (with retry-on-halt + quality-gate retry) ─────────
run_dev_story() {
  local extra_context="$1"
  claude --print \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep,mcp__serena__*,mcp__code-graph__*" \
    --model claude-sonnet-4-6 \
    --max-turns 50 \
    --mcp-config "$MCP_CONFIG" \
    "PROJECT_ROOT: $REPO_ROOT
PLANNING_DIR: $PLANNING_DIR
implementation_artifacts: $STORIES_DIR
project-root: $REPO_ROOT
ALL_REPO_ROOTS: $(for r in "${INVOLVED_REPOS[@]}"; do echo -n "/tmp/oracle-work/workspace/$r "; done)

## Codebase Navigation (use BEFORE Read)
- mcp__serena__find_symbol — look up function/class by name
- mcp__serena__get_file_outline — symbols in a file without reading it
- mcp__serena__find_references — call sites of a symbol
- mcp__code-graph__semantic_search — find code by description
- Read with offset+limit (50-100 lines) only when needed

$(cat "$WF_DEV_STORY")

Story file: $STORY_FILE
Scope: touch only — $STORY_AFFECTED_MODULES
${extra_context}
AUTONOMOUS MODE: Implement all tasks. Run tests after each task. No pauses.
Last line JSON: {\"status\":\"review|halted\",\"tasks_done\":0,\"halt_reason\":\"\"}" 2>&1
}

DEV_OUT=$(run_dev_story "")
DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null || echo "halted")

if [ "$DEV_STATUS" = "halted" ]; then
  HALT=$(echo "$DEV_OUT" | tail -1 | jq -r '.halt_reason' 2>/dev/null || echo "unknown")
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Story \`$STORY_KEY\` halted: $HALT — retrying once"
  DEV_OUT=$(run_dev_story "Previous halt reason: $HALT — resolve and complete.")
  DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null || echo "halted")
fi

if [ "$DEV_STATUS" = "halted" ]; then
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Story \`$STORY_KEY\` failed after retry."
  echo "### Story $STORY_KEY — FAILED" >> /tmp/oracle-work/PIPELINE.md
  exit 1
fi

# ── Step 3: Quality gates (lint + test + coverage) ───────────────────────────
GATE_FAILS=""
if ! "$SCRIPT_DIR/lint-check.sh" "$REPO_ROOT"; then
  GATE_FAILS="${GATE_FAILS}lint "
fi
if ! "$SCRIPT_DIR/check-coverage.sh" "$REPO_ROOT"; then
  GATE_FAILS="${GATE_FAILS}tests/coverage "
fi

if [ -n "$GATE_FAILS" ]; then
  echo "Quality gates failed: $GATE_FAILS — re-running dev-story to fix"
  DEV_OUT=$(run_dev_story "Quality gates failed: $GATE_FAILS. Fix lint errors, failing tests, and ensure coverage ≥ 80% on new code.")
  DEV_STATUS=$(echo "$DEV_OUT" | tail -1 | jq -r '.status' 2>/dev/null || echo "halted")

  GATE_FAILS=""
  "$SCRIPT_DIR/lint-check.sh"     "$REPO_ROOT" || GATE_FAILS="${GATE_FAILS}lint "
  "$SCRIPT_DIR/check-coverage.sh" "$REPO_ROOT" || GATE_FAILS="${GATE_FAILS}tests/coverage "
  if [ -n "$GATE_FAILS" ]; then
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "Story \`$STORY_KEY\` failed quality gates after retry: $GATE_FAILS"
    echo "### Story $STORY_KEY — FAILED (gates)" >> /tmp/oracle-work/PIPELINE.md
    exit 1
  fi
fi

# ── Step 4: bmad-code-review (re-run dev once on changes_requested) ──────────
REVIEW_OUT=$(claude --print \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
  --model claude-sonnet-4-6 \
  "PROJECT_ROOT: $REPO_ROOT
PLANNING_DIR: $PLANNING_DIR

$(cat "$WF_CODE_REVIEW")

Story file: $STORY_FILE
Last line JSON: {\"status\":\"approved|changes_requested\",\"findings_high\":0}" 2>&1)

REVIEW_STATUS=$(echo "$REVIEW_OUT" | tail -1 | jq -r '.status' 2>/dev/null || echo "approved")

if [ "$REVIEW_STATUS" = "changes_requested" ]; then
  claude --print \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
    --model claude-sonnet-4-6 \
    --max-turns 20 \
    "PROJECT_ROOT: $REPO_ROOT
$(cat "$WF_DEV_STORY")
Story file: $STORY_FILE
Address all code review findings. High severity first.
Last line JSON: {\"status\":\"done\"}" 2>&1 | tail -3
fi

# ── Step 5: Atomic commit per repo ───────────────────────────────────────────
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "/tmp/oracle-work/workspace/$REPO"
  if ! git diff --quiet HEAD 2>/dev/null || git status --porcelain | grep -q .; then
    "$SCRIPT_DIR/pre-commit-check.sh" "$PWD" || {
      echo "Pre-commit check failed in $REPO — aborting story"
      cd /tmp/oracle-work
      exit 1
    }
    git add -A
    git commit -m "[Story $STORY_KEY] $STORY_TITLE"
    echo "Committed in $REPO"
  fi
  cd /tmp/oracle-work
done

echo "### Story $STORY_KEY — COMPLETE" >> /tmp/oracle-work/PIPELINE.md
exit 0
