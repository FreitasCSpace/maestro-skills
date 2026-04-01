#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# CareSpace PM Context — Single source of truth for all PM skills
# Ported from carespace-pm-crews/shared/config/context.py (2026-03-17)
# ═══════════════════════════════════════════════════════════════════════

export WORKSPACE_ID="31124097"
export GITHUB_ORG="carespace-ai"

# ── SPACES ────────────────────────────────────────────────────────────
export SPACE_ENGINE="901313687155"
export SPACE_GTM="901313687157"

# ── FOLDERS ───────────────────────────────────────────────────────────
export FOLDER_BACKLOG="901317811713"
export FOLDER_SPRINT_PLANNING="901317852083"
export FOLDER_SPRINTS="901317811717"
export FOLDER_OPERATIONS="901317811718"
export FOLDER_PLAYBOOKS="901317811721"
export FOLDER_PIPELINE="901317811738"
export FOLDER_MARKETING="901317811726"
export FOLDER_CS="901317811730"

# ── LIST IDs (the only IDs skills need) ───────────────────────────────
export LIST_MASTER_BACKLOG="901326439232"
export LIST_SPRINT_CANDIDATES="901326510572"
export LIST_ALERTS="901326439234"
export LIST_SPRINT_HISTORY="901326439238"
export LIST_ACTIVE_DEALS="901326439255"
export LIST_AT_RISK_DEALS="901326439258"
export LIST_CONTENT_CAMPAIGNS="901326439261"
export LIST_PRODUCT_LAUNCHES="901326439262"
export LIST_ONBOARDING="901326439266"
export LIST_SUPPORT_ESCALATIONS="901326439271"
export SPRINT_TEMPLATE_LIST="901326512991"

# ── CUSTOM FIELD IDs ──────────────────────────────────────────────────
# CORRECT SP field from carespace-pm-crews-final context.py
export SP_FIELD_ID="1662e3e7-b018-47b7-8881-e30f6831c674"

# ── SLACK CHANNELS (APPROVED LIST — NEVER post to any other channel) ──
# ⛔ FORBIDDEN: Do NOT post to #carespace-team, #general, or any channel
#    not listed here. If unsure, use $SLACK_ENGINEERING.
export SLACK_STANDUP="#pm-standup"
export SLACK_SPRINT="#pm-sprint-board"
export SLACK_ENGINEERING="#pm-engineering"
export SLACK_ALERTS="#pm-alerts"
export SLACK_GTM="#pm-gtm"
export SLACK_EXEC="#pm-exec-updates"
export SLACK_COMPLIANCE="#pm-compliance"
export SLACK_CS="#pm-customer-success"
export SLACK_OPS="#ops-general"
# Allowed channels array for validation
export SLACK_ALLOWED_CHANNELS="pm-standup pm-sprint-board pm-engineering pm-alerts pm-gtm pm-exec-updates pm-compliance pm-customer-success ops-general"

# ── SPRINT RULES ──────────────────────────────────────────────────────
export SPRINT_BUDGET_SP=48        # 60 default velocity * 0.80 buffer
export SPRINT_MIN_FEATURES=3
export SPRINT_MAX_COMPLIANCE=3
export SPRINT_TARGET_ITEMS="10-12"
export SPRINT_MIX="1-2 bugs + 3-5 features + 2-3 tasks + 2-3 compliance"

# ── SP ESTIMATION ─────────────────────────────────────────────────────
# security=8, bug_low=2, bug_medium=5, bug_high=8
# feature_small=5, feature_medium=13, feature_large=21
# pr_review=2, ci_fix=3

# ── BUG SLA (hours) ──────────────────────────────────────────────────
# urgent=4h, high=24h, normal=72h, low=168h

# ── THRESHOLDS ────────────────────────────────────────────────────────
export STALE_PR_DAYS=7
export STALE_TASK_DAYS=3
export AGING_TASK_DAYS=21

# ── REPO → DOMAIN ROUTING ────────────────────────────────────────────
# All issues go to master_backlog with domain tags
declare -A REPO_DOMAIN=(
  ["carespace-ui"]="frontend" ["carespace-landingpage"]="frontend" ["carespace-site"]="frontend"
  ["CareSpace-LMS"]="frontend" ["meta-web-view"]="frontend" ["healthstartiq"]="frontend"
  ["carespace-admin"]="backend" ["carespace-api-gateway"]="backend" ["carespace-strapi"]="backend"
  ["carespace-mobile-android"]="mobile" ["carespace-mobile-ios"]="mobile" ["carespace_mobile"]="mobile"
  ["carespace-sdk"]="sdk" ["PoseEstimator"]="ai-cv" ["carespace-poseestimation"]="ai-cv"
  ["carespace-posture-engine"]="ai-cv" ["carespace-botkit"]="bots" ["carespace-chat"]="bots"
  ["carespace-media-converter"]="video" ["carespace-video-converter"]="video"
  ["carespace-docker"]="infra" ["carespace-fusionauth"]="infra" ["carespace-monitoring"]="infra"
  ["carespace-bug-tracker"]="infra"
)

# ── DOMAIN LEADS (ClickUp user IDs) ──────────────────────────────────
declare -A DOMAIN_LEAD=(
  ["frontend"]="49000180" ["backend"]="49000181" ["mobile"]="93908270"
  ["ai-cv"]="93908266" ["sdk"]="93908270" ["infra"]="111928715"
  ["bots"]="49000181" ["video"]="93908266"
  ["security"]="93908266" ["compliance"]="118004891"
)

# ── CI CHECK REPOS ────────────────────────────────────────────────────
export CI_REPOS="carespace-ui carespace-admin carespace-api-gateway carespace-sdk"

# ── COMPLIANCE ────────────────────────────────────────────────────────
export COMPLIANCE_REPO="FreitasCSpace/CareSpace-Compliance-Repo"

# ── Helper: ClickUp API with retry ───────────────────────────────────
cu_api() {
  local method="${1:-GET}" endpoint="$2" data="$3"
  local url="https://api.clickup.com/api/v2/$endpoint"
  local args=(-s -X "$method" -H "Authorization: $CLICKUP_PERSONAL_TOKEN" -H "Content-Type: application/json")
  [ -n "$data" ] && args+=(-d "$data")

  for attempt in 1 2 3; do
    RESP=$(curl "${args[@]}" "$url" 2>/dev/null)
    if echo "$RESP" | grep -q '"err".*"Rate limit'; then
      sleep $((attempt * 2))
      continue
    fi
    echo "$RESP"
    return 0
  done
  echo '{"error":"Rate limited after 3 retries"}'
  return 1
}

# ── Helper: Get domain tag for a repo ─────────────────────────────────
get_domain() {
  local repo="$1"
  echo "${REPO_DOMAIN[$repo]:-other}"
}

# ── Helper: Post Block Kit message to Slack (idempotent) ────────────
# Usage: slack_post "#channel" "Title" "Body markdown" "skill-name"
# Searches for existing message with same title today — updates if found, posts new if not.
# ⛔ REFUSES to post to channels not in SLACK_ALLOWED_CHANNELS.
slack_post() {
  local channel="$1" title="$2" body="$3" skill="$4"
  local today=$(date +%Y-%m-%d)
  local ch_name="${channel#\#}"

  # GUARDRAIL: Only post to approved channels
  if ! echo "$SLACK_ALLOWED_CHANNELS" | grep -qw "$ch_name"; then
    echo "⛔ BLOCKED: $ch_name is NOT an approved Slack channel."
    echo "   Approved: $SLACK_ALLOWED_CHANNELS"
    echo "   Skill $skill tried to post to unauthorized channel. Aborting."
    return 1
  fi

  # Find channel ID
  local ch_id=$(curl -s "https://slack.com/api/conversations.list?types=public_channel&limit=200" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq -r --arg name "${channel#\#}" '.channels[]|select(.name==$name)|.id')

  if [ -z "$ch_id" ]; then
    echo "ERROR: Channel $channel not found"
    return 1
  fi

  # Truncate body to 2800 chars for Block Kit limit
  local body_trunc="${body:0:2800}"

  # Build Block Kit blocks
  local blocks=$(jq -n \
    --arg title "$title" \
    --arg body "$body_trunc" \
    --arg footer "_${title} by CareSpace PM AI via ClaudeHub — $today_" \
    '[
      {"type":"header","text":{"type":"plain_text","text":$title}},
      {"type":"section","text":{"type":"mrkdwn","text":$body}},
      {"type":"divider"},
      {"type":"context","elements":[{"type":"mrkdwn","text":$footer}]}
    ]')

  # Search for existing message today to update (idempotent)
  local oldest=$(date -d 'today 00:00' +%s 2>/dev/null || echo $(($(date +%s) - 86400)))
  local existing_ts=$(curl -s "https://slack.com/api/conversations.history?channel=$ch_id&oldest=$oldest&limit=50" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    | jq -r --arg t "$title" '.messages[]|select(.blocks[0].text.text==$t)|.ts' | head -1)

  if [ -n "$existing_ts" ] && [ "$existing_ts" != "null" ]; then
    # Update existing message
    curl -s -X POST "https://slack.com/api/chat.update" \
      -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg ch "$ch_id" --arg ts "$existing_ts" --argjson blocks "$blocks" \
        '{channel:$ch,ts:$ts,blocks:$blocks}')" > /dev/null
    echo "UPDATED existing Slack message in $channel"
  else
    # Post new message
    curl -s -X POST "https://slack.com/api/chat.postMessage" \
      -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg ch "$ch_id" --argjson blocks "$blocks" --arg text "$title" \
        '{channel:$ch,text:$text,blocks:$blocks}')" > /dev/null
    echo "POSTED new Slack message to $channel"
  fi
}

echo "PM context loaded — workspace $WORKSPACE_ID"
