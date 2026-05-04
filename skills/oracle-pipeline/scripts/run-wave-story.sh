#!/usr/bin/env bash
# run-wave-story.sh — single-story runner invoked by a parallel Task agent.
#
# Differs from 03-run-story.sh only in environment management:
#   - Reads workspace from ORACLE_WORK (set by spawning Task tool)
#   - Sources the same env.0N.sh files from that workspace
#   - Forwards exit code so the spawning agent can report back
#
# Args identical to 03-run-story.sh:
#   $1 = EPIC_NUM   $2 = STORY_NUM   $3 = STORY_TITLE
#
# Required env (set by the Task agent prompt):
#   ORACLE_WORK   path to the worktree-isolated /tmp/oracle-work-N
set -euo pipefail

: "${ORACLE_WORK:?ORACLE_WORK must be set by spawning Task agent}"
[ -f "$ORACLE_WORK/env.00.sh" ] || { echo "BLOCKED: $ORACLE_WORK not provisioned"; exit 1; }

. "$ORACLE_WORK/env.00.sh"
. "$ORACLE_WORK/env.01.sh"
. "$ORACLE_WORK/env.02.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Re-route 03-run-story to the agent-local workspace
ln -sfn "$ORACLE_WORK" /tmp/oracle-work 2>/dev/null || true
exec "$SCRIPT_DIR/03-run-story.sh" "$1" "$2" "$3"
