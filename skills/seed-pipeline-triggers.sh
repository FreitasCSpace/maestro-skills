#!/bin/bash
# Seed the autonomous pipeline chain triggers in Maestro.
#
# IMPORTANT: All chain triggers use pipeline-* wrapper skills ONLY.
# Native gstack skills (review, qa, cso, etc.) are NEVER chained —
# they stay standalone. This prevents infinite trigger loops.
#
# Usage:
#   export MAESTRO_TOKEN="your-api-token"
#   export BASE_URL="http://localhost:8000"
#   bash seed-pipeline-triggers.sh [--feature | --bug-fix | --all]
#
set -e

API="${BASE_URL:-http://localhost:8000}/api/v1"
AUTH="Authorization: Bearer ${MAESTRO_TOKEN:?MAESTRO_TOKEN required}"
CT="Content-Type: application/json"
MODE="${1:---all}"

echo "=== Seeding Pipeline Chain Triggers (wrapper skills only) ==="
echo "API: $API"
echo "Mode: $MODE"

# ── Helper: get crew_def_id by skill name ──────────────────────────────────
get_crew_id() {
  curl -s -H "$AUTH" "$API/skills" | \
    python3 -c "import sys,json; skills=json.load(sys.stdin); ids=[s['crew_def_id'] for s in skills if s['name']=='$1']; print(ids[0] if ids else '')" 2>/dev/null
}

# ── Helper: create chain trigger ───────────────────────────────────────────
create_trigger() {
  local name="$1" source_id="$2" target_id="$3" trigger_type="$4" project="${5:-pipeline}"

  if [ -z "$source_id" ] || [ -z "$target_id" ]; then
    echo "  SKIP: $name (missing skill ID — sync skills first)"
    return 1
  fi

  echo -n "  $name... "
  curl -s -X POST "$API/schedules" \
    -H "$AUTH" -H "$CT" \
    -d "{
      \"name\": \"$name\",
      \"crew_def_id\": \"$target_id\",
      \"source_crew_def_id\": \"$source_id\",
      \"trigger_type\": \"$trigger_type\",
      \"project_name\": \"$project\",
      \"is_enabled\": true
    }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'OK ({r.get(\"id\",\"?\")[:8]})')" 2>/dev/null || echo "FAILED"
}

# ── Look up pipeline-* wrapper skill IDs ───────────────────────────────────
echo ""
echo "Looking up pipeline-* wrapper skill IDs..."
echo "(Only pipeline-* skills get chain triggers — never native gstack skills)"

ID_START=$(get_crew_id "pipeline-start")
ID_THINK=$(get_crew_id "pipeline-think")
ID_PLAN=$(get_crew_id "pipeline-plan")
ID_INVESTIGATE=$(get_crew_id "pipeline-investigate")
ID_FIX=$(get_crew_id "pipeline-fix")
ID_REVIEW=$(get_crew_id "pipeline-review")
ID_SECURITY=$(get_crew_id "pipeline-security")
ID_QA=$(get_crew_id "pipeline-qa")
ID_SHIP=$(get_crew_id "pipeline-ship")
ID_DEPLOY=$(get_crew_id "pipeline-deploy")
ID_CANARY=$(get_crew_id "pipeline-canary")
ID_DOCS=$(get_crew_id "pipeline-docs")
ID_RETRO=$(get_crew_id "pipeline-retro")

echo ""
echo "  pipeline-start:       ${ID_START:-MISSING}"
echo "  pipeline-think:       ${ID_THINK:-MISSING}"
echo "  pipeline-plan:        ${ID_PLAN:-MISSING}"
echo "  pipeline-investigate: ${ID_INVESTIGATE:-MISSING}"
echo "  pipeline-fix:         ${ID_FIX:-MISSING}"
echo "  pipeline-review:      ${ID_REVIEW:-MISSING}"
echo "  pipeline-security:    ${ID_SECURITY:-MISSING}"
echo "  pipeline-qa:          ${ID_QA:-MISSING}"
echo "  pipeline-ship:        ${ID_SHIP:-MISSING}"
echo "  pipeline-deploy:      ${ID_DEPLOY:-MISSING}"
echo "  pipeline-canary:      ${ID_CANARY:-MISSING}"
echo "  pipeline-docs:        ${ID_DOCS:-MISSING}"
echo "  pipeline-retro:       ${ID_RETRO:-MISSING}"

# ═══════════════════════════════════════════════════════════════════════════
# FEATURE PIPELINE (full sprint)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "--feature" ] || [ "$MODE" = "--all" ]; then
  echo ""
  echo "── Feature Pipeline ────────────────────────────────────────────────"
  echo "   start → think → plan → fix → review → security → qa → ship"
  echo "   → deploy → canary → docs → retro"

  create_trigger "feat: start → think"         "$ID_START"    "$ID_THINK"    "on_success" "pipeline-feature"
  create_trigger "feat: think → plan"          "$ID_THINK"    "$ID_PLAN"     "on_success" "pipeline-feature"
  create_trigger "feat: plan → fix"            "$ID_PLAN"     "$ID_FIX"      "on_success" "pipeline-feature"
  create_trigger "feat: fix → review"          "$ID_FIX"      "$ID_REVIEW"   "on_success" "pipeline-feature"
  create_trigger "feat: review → security"     "$ID_REVIEW"   "$ID_SECURITY" "on_success" "pipeline-feature"
  create_trigger "feat: security → qa"         "$ID_SECURITY" "$ID_QA"       "on_success" "pipeline-feature"
  create_trigger "feat: qa → ship"             "$ID_QA"       "$ID_SHIP"     "on_success" "pipeline-feature"
  create_trigger "feat: ship → deploy"         "$ID_SHIP"     "$ID_DEPLOY"   "on_success" "pipeline-feature"
  create_trigger "feat: deploy → canary"       "$ID_DEPLOY"   "$ID_CANARY"   "on_success" "pipeline-feature"
  create_trigger "feat: canary → docs"         "$ID_CANARY"   "$ID_DOCS"     "on_success" "pipeline-feature"
  create_trigger "feat: docs → retro"          "$ID_DOCS"     "$ID_RETRO"    "on_success" "pipeline-feature"

  echo ""
  echo "  Feedback loops (BLOCK → re-fix):"
  create_trigger "feat: review BLOCKED → fix"    "$ID_REVIEW"   "$ID_FIX" "on_failure" "pipeline-feature"
  create_trigger "feat: security BLOCKED → fix"  "$ID_SECURITY" "$ID_FIX" "on_failure" "pipeline-feature"
  create_trigger "feat: qa FAILED → fix"         "$ID_QA"       "$ID_FIX" "on_failure" "pipeline-feature"
fi

# ═══════════════════════════════════════════════════════════════════════════
# BUG FIX PIPELINE (skip think/plan, add investigate)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "--bug-fix" ] || [ "$MODE" = "--all" ]; then
  echo ""
  echo "── Bug Fix Pipeline ────────────────────────────────────────────────"
  echo "   start → investigate → fix → review → security → qa → ship"
  echo "   → deploy → canary → retro"

  create_trigger "bug: start → investigate"      "$ID_START"       "$ID_INVESTIGATE" "on_success" "pipeline-bugfix"
  create_trigger "bug: investigate → fix"         "$ID_INVESTIGATE" "$ID_FIX"         "on_success" "pipeline-bugfix"
  create_trigger "bug: fix → review"              "$ID_FIX"         "$ID_REVIEW"      "on_success" "pipeline-bugfix"
  create_trigger "bug: review → security"         "$ID_REVIEW"      "$ID_SECURITY"    "on_success" "pipeline-bugfix"
  create_trigger "bug: security → qa"             "$ID_SECURITY"    "$ID_QA"          "on_success" "pipeline-bugfix"
  create_trigger "bug: qa → ship"                 "$ID_QA"          "$ID_SHIP"        "on_success" "pipeline-bugfix"
  create_trigger "bug: ship → deploy"             "$ID_SHIP"        "$ID_DEPLOY"      "on_success" "pipeline-bugfix"
  create_trigger "bug: deploy → canary"           "$ID_DEPLOY"      "$ID_CANARY"      "on_success" "pipeline-bugfix"
  create_trigger "bug: canary → retro"            "$ID_CANARY"      "$ID_RETRO"       "on_success" "pipeline-bugfix"

  echo ""
  echo "  Feedback loops (BLOCK → re-fix):"
  create_trigger "bug: review BLOCKED → fix"      "$ID_REVIEW"   "$ID_FIX" "on_failure" "pipeline-bugfix"
  create_trigger "bug: security BLOCKED → fix"    "$ID_SECURITY" "$ID_FIX" "on_failure" "pipeline-bugfix"
  create_trigger "bug: qa FAILED → fix"           "$ID_QA"       "$ID_FIX" "on_failure" "pipeline-bugfix"
fi

echo ""
echo "=== Done ==="
echo ""
echo "IMPORTANT: Only pipeline-* wrapper skills have chain triggers."
echo "Native gstack skills (review, qa, cso, etc.) are standalone — no triggers."
echo ""
echo "To start a pipeline: Maestro UI → Skills → pipeline-start → Trigger"
echo "Input: {\"task\": \"your task description here\"}"
