#!/bin/bash
# Seed the autonomous pipeline chain triggers in Maestro.
#
# This wires native gstack skills into a full sprint pipeline:
#   Think → Plan → Build → Review → Test → Ship → Reflect
#
# Custom skills: pipeline-start, pipeline-fix (build phase)
# Native gstack: office-hours, autoplan, investigate, review, cso, qa, ship,
#                land-and-deploy, canary, document-release, retro
#
# Prerequisites:
#   1. Maestro API running at $BASE_URL
#   2. Skills synced (POST /skills/sync-to-runs)
#   3. Admin API token
#
# Usage:
#   export MAESTRO_TOKEN="your-api-token"
#   export BASE_URL="http://localhost:8000"
#   bash seed-pipeline-triggers.sh [--bug-fix | --feature | --all]
#
set -e

API="${BASE_URL:-http://localhost:8000}/api/v1"
AUTH="Authorization: Bearer ${MAESTRO_TOKEN:?MAESTRO_TOKEN required}"
CT="Content-Type: application/json"
MODE="${1:---all}"

echo "=== Seeding Pipeline Chain Triggers ==="
echo "API: $API"
echo "Mode: $MODE"

# ── Helper: get crew_def_id by skill name ──────────────────────────────────
get_crew_id() {
  local id
  id=$(curl -s -H "$AUTH" "$API/skills" | \
    python3 -c "import sys,json; skills=json.load(sys.stdin); print(next((s['crew_def_id'] for s in skills if s['name']=='$1'), ''))" 2>/dev/null)
  echo "$id"
}

# ── Helper: create chain trigger ───────────────────────────────────────────
create_trigger() {
  local name="$1" source_id="$2" target_id="$3" trigger_type="$4" project="${5:-pipeline}"

  if [ -z "$source_id" ] || [ -z "$target_id" ]; then
    echo "  SKIP: $name (missing skill ID)"
    return
  fi

  echo -n "  $name... "
  local resp
  resp=$(curl -s -X POST "$API/schedules" \
    -H "$AUTH" -H "$CT" \
    -d "{
      \"name\": \"$name\",
      \"crew_def_id\": \"$target_id\",
      \"source_crew_def_id\": \"$source_id\",
      \"trigger_type\": \"$trigger_type\",
      \"project_name\": \"$project\",
      \"is_enabled\": true
    }")
  echo "$resp" | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'OK (id={r.get(\"id\",\"?\")[:8]})')" 2>/dev/null || echo "FAILED"
}

# ── Look up all skill IDs ──────────────────────────────────────────────────
echo ""
echo "Looking up skill IDs..."

# Custom pipeline skills
ID_START=$(get_crew_id "pipeline-start")
ID_FIX=$(get_crew_id "pipeline-fix")

# Native gstack skills
ID_OFFICE_HOURS=$(get_crew_id "office-hours")
ID_AUTOPLAN=$(get_crew_id "autoplan")
ID_INVESTIGATE=$(get_crew_id "investigate")
ID_REVIEW=$(get_crew_id "review")
ID_CSO=$(get_crew_id "cso")
ID_QA=$(get_crew_id "qa")
ID_SHIP=$(get_crew_id "ship")
ID_LAND=$(get_crew_id "land-and-deploy")
ID_CANARY=$(get_crew_id "canary")
ID_DOCS=$(get_crew_id "document-release")
ID_RETRO=$(get_crew_id "retro")
ID_DESIGN_REVIEW=$(get_crew_id "design-review")

echo ""
echo "  Custom:  pipeline-start=$ID_START  pipeline-fix=$ID_FIX"
echo "  Think:   office-hours=$ID_OFFICE_HOURS"
echo "  Plan:    autoplan=$ID_AUTOPLAN"
echo "  Debug:   investigate=$ID_INVESTIGATE"
echo "  Review:  review=$ID_REVIEW  design-review=$ID_DESIGN_REVIEW"
echo "  Secure:  cso=$ID_CSO"
echo "  Test:    qa=$ID_QA"
echo "  Ship:    ship=$ID_SHIP"
echo "  Deploy:  land-and-deploy=$ID_LAND  canary=$ID_CANARY"
echo "  Docs:    document-release=$ID_DOCS"
echo "  Retro:   retro=$ID_RETRO"

# ═══════════════════════════════════════════════════════════════════════════
# FEATURE PIPELINE (full sprint)
# Think → Plan → Build → Review → Security → QA → Ship → Deploy → Canary → Docs → Retro
# ═══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "--feature" ] || [ "$MODE" = "--all" ]; then
  echo ""
  echo "── Feature Pipeline (full sprint) ──────────────────────────────────"

  create_trigger "feature: start → office-hours"        "$ID_START"         "$ID_OFFICE_HOURS"  "on_success" "pipeline-feature"
  create_trigger "feature: office-hours → autoplan"     "$ID_OFFICE_HOURS"  "$ID_AUTOPLAN"      "on_success" "pipeline-feature"
  create_trigger "feature: autoplan → fix"              "$ID_AUTOPLAN"      "$ID_FIX"           "on_success" "pipeline-feature"
  create_trigger "feature: fix → review"                "$ID_FIX"           "$ID_REVIEW"        "on_success" "pipeline-feature"
  create_trigger "feature: review → cso"                "$ID_REVIEW"        "$ID_CSO"           "on_success" "pipeline-feature"
  create_trigger "feature: cso → qa"                    "$ID_CSO"           "$ID_QA"            "on_success" "pipeline-feature"
  create_trigger "feature: qa → ship"                   "$ID_QA"            "$ID_SHIP"          "on_success" "pipeline-feature"
  create_trigger "feature: ship → land-and-deploy"      "$ID_SHIP"          "$ID_LAND"          "on_success" "pipeline-feature"
  create_trigger "feature: land-and-deploy → canary"    "$ID_LAND"          "$ID_CANARY"        "on_success" "pipeline-feature"
  create_trigger "feature: canary → document-release"   "$ID_CANARY"        "$ID_DOCS"          "on_success" "pipeline-feature"
  create_trigger "feature: document-release → retro"    "$ID_DOCS"          "$ID_RETRO"         "on_success" "pipeline-feature"

  echo ""
  echo "  Feedback loops (BLOCK → re-fix):"
  create_trigger "feature: review BLOCKED → fix"        "$ID_REVIEW"  "$ID_FIX" "on_failure" "pipeline-feature"
  create_trigger "feature: cso BLOCKED → fix"           "$ID_CSO"     "$ID_FIX" "on_failure" "pipeline-feature"
  create_trigger "feature: qa FAILED → fix"             "$ID_QA"      "$ID_FIX" "on_failure" "pipeline-feature"
fi

# ═══════════════════════════════════════════════════════════════════════════
# BUG FIX PIPELINE (skip think/plan, add investigate)
# Investigate → Build → Review → Security → QA → Ship → Deploy → Canary → Retro
# ═══════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "--bug-fix" ] || [ "$MODE" = "--all" ]; then
  echo ""
  echo "── Bug Fix Pipeline (investigate-first) ────────────────────────────"

  create_trigger "bugfix: start → investigate"          "$ID_START"       "$ID_INVESTIGATE"  "on_success" "pipeline-bugfix"
  create_trigger "bugfix: investigate → fix"            "$ID_INVESTIGATE" "$ID_FIX"          "on_success" "pipeline-bugfix"
  create_trigger "bugfix: fix → review"                 "$ID_FIX"         "$ID_REVIEW"       "on_success" "pipeline-bugfix"
  create_trigger "bugfix: review → cso"                 "$ID_REVIEW"      "$ID_CSO"          "on_success" "pipeline-bugfix"
  create_trigger "bugfix: cso → qa"                     "$ID_CSO"         "$ID_QA"           "on_success" "pipeline-bugfix"
  create_trigger "bugfix: qa → ship"                    "$ID_QA"          "$ID_SHIP"         "on_success" "pipeline-bugfix"
  create_trigger "bugfix: ship → land-and-deploy"       "$ID_SHIP"        "$ID_LAND"         "on_success" "pipeline-bugfix"
  create_trigger "bugfix: land-and-deploy → canary"     "$ID_LAND"        "$ID_CANARY"       "on_success" "pipeline-bugfix"
  create_trigger "bugfix: canary → retro"               "$ID_CANARY"      "$ID_RETRO"        "on_success" "pipeline-bugfix"

  echo ""
  echo "  Feedback loops (BLOCK → re-fix):"
  create_trigger "bugfix: review BLOCKED → fix"         "$ID_REVIEW"  "$ID_FIX" "on_failure" "pipeline-bugfix"
  create_trigger "bugfix: cso BLOCKED → fix"            "$ID_CSO"     "$ID_FIX" "on_failure" "pipeline-bugfix"
  create_trigger "bugfix: qa FAILED → fix"              "$ID_QA"      "$ID_FIX" "on_failure" "pipeline-bugfix"
fi

echo ""
echo "=== Pipeline triggers seeded ==="
echo ""
echo "To start a FEATURE pipeline:"
echo "  curl -X POST \$API/skills/pipeline-start/trigger \\"
echo "    -H 'Authorization: Bearer \$MAESTRO_TOKEN' -H 'Content-Type: application/json' \\"
echo "    -d '{\"input_kwargs\": {\"task\": \"Add dark mode toggle to settings page\"}}'"
echo ""
echo "To start a BUG FIX pipeline:"
echo "  curl -X POST \$API/skills/pipeline-start/trigger \\"
echo "    -H 'Authorization: Bearer \$MAESTRO_TOKEN' -H 'Content-Type: application/json' \\"
echo "    -d '{\"input_kwargs\": {\"task\": \"Fix login crash on mobile Safari\"}}'"
