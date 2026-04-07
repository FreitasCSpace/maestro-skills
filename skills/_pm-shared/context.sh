#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# CareSpace PM Context — Single source of truth for all PM skills
# Ported from carespace-pm-crews/shared/config/context.py (2026-03-17)
# ═══════════════════════════════════════════════════════════════════════
#
# ⛔⛔⛔ ABSOLUTE RULES — DO NOT VIOLATE UNDER ANY CIRCUMSTANCES ⛔⛔⛔
#
# 1. ONLY post to Slack channels listed in SLACK_ALLOWED_CHANNELS below.
#    NEVER substitute, fallback, or "helpfully" pick a different channel.
#    If the target channel doesn't exist, FAIL and report the error.
#    DO NOT post to #carespace-team, #general, #eng-general, or ANY
#    channel not explicitly listed. No exceptions. No "instead" logic.
#
# 2. ONLY use IDs, field names, and values defined in this file.
#    NEVER guess, infer, or substitute different values.
#
# 3. Follow the SKILL.md steps EXACTLY. Do not skip, reorder, or
#    improvise alternatives. If a step fails, report the failure.
#
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

# Allowed channels array for validation
export SLACK_ALLOWED_CHANNELS="pm-standup pm-sprint-board pm-engineering"

# ── HUDDLE NOTES ──────────────────────────────────────────────────────
# READ-ONLY source channels for huddle notes (never posted to — read only)
# carespace-team is forbidden for posting but safe to READ for archival
export HUDDLE_SOURCE_CHANNELS="pm-standup carespace-team"
export HUDDLE_LOOKBACK_DAYS=7
export HUDDLE_VAULT_REPO="carespace-ai/carespace-pm-vault"
export HUDDLE_VAULT_PATH="huddles"
export HUDDLE_MAX_PER_RUN=20
export HUDDLE_MIN_CONTENT_CHARS=50

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
  local hdr=/tmp/.cu-hdr.$$
  local args=(-sS -D "$hdr" -X "$method" \
    -H "Authorization: $CLICKUP_PERSONAL_TOKEN" \
    -H "Content-Type: application/json")
  [ -n "$data" ] && args+=(-d "$data")

  for attempt in 1 2 3 4 5; do
    RESP=$(curl "${args[@]}" "$url" 2>/dev/null)
    local code=$(awk 'NR==1{print $2}' "$hdr" 2>/dev/null)
    if [ "$code" = "429" ] || echo "$RESP" | grep -q '"err".*"Rate limit'; then
      local ra=$(awk 'tolower($1)=="retry-after:"{gsub("\r","",$2); print $2}' "$hdr")
      [ -z "$ra" ] && ra=$((attempt * 5))
      sleep "$ra"
      continue
    fi
    rm -f "$hdr"
    echo "$RESP"
    return 0
  done
  rm -f "$hdr"
  echo '{"error":"Rate limited after 5 retries"}'
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

  # Find channel ID — paginate, search public + private channels
  local ch_id="" cursor=""
  while true; do
    local url="https://slack.com/api/conversations.list?types=public_channel,private_channel&limit=200"
    [ -n "$cursor" ] && url="${url}&cursor=${cursor}"
    local page
    page=$(curl -s "$url" -H "Authorization: Bearer $SLACK_BOT_TOKEN")
    ch_id=$(echo "$page" | jq -r --arg n "$ch_name" '.channels[]|select(.name==$n)|.id' | head -1)
    [ -n "$ch_id" ] && break
    cursor=$(echo "$page" | jq -r '.response_metadata.next_cursor // empty')
    [ -z "$cursor" ] && break
  done

  if [ -z "$ch_id" ]; then
    echo "ERROR: Channel #${ch_name} not found via conversations.list."
    echo "  Possible causes:"
    echo "  1. Bot not invited — run: /invite @<botname> in #${ch_name}"
    echo "  2. Missing scope — bot token needs channels:read (public) or groups:read (private)"
    echo "  3. Channel name mismatch — check exact name in Slack workspace"
    return 1
  fi

  # Chunk body into ≤2900-char pieces on paragraph boundaries (Block Kit section limit = 3000)
  # Writes one JSON file per chunk, then jq-merges into a blocks array.
  local chunk_dir=/tmp/.slack-chunks.$$
  rm -rf "$chunk_dir"; mkdir -p "$chunk_dir"
  awk -v dir="$chunk_dir" '
    BEGIN { buf=""; n=0 }
    {
      line = $0 "\n"
      if (length(buf) + length(line) > 2900 && length(buf) > 0) {
        n++; printf "%s", buf > sprintf("%s/%04d.txt", dir, n); close(sprintf("%s/%04d.txt", dir, n))
        buf = ""
      }
      buf = buf line
    }
    END {
      if (length(buf) > 0) {
        n++; printf "%s", buf > sprintf("%s/%04d.txt", dir, n); close(sprintf("%s/%04d.txt", dir, n))
      }
    }
  ' <<< "$body"

  # Build section blocks from each chunk file
  local section_blocks
  section_blocks=$(for f in "$chunk_dir"/*.txt; do
    jq -Rs '{type:"section",text:{type:"mrkdwn",text:.}}' < "$f"
  done | jq -s '.')
  rm -rf "$chunk_dir"

  local blocks=$(jq -n \
    --arg title "$title" \
    --argjson sections "$section_blocks" \
    --arg footer "_${title} by CareSpace PM AI via ClaudeHub — $today_" \
    '[{"type":"header","text":{"type":"plain_text","text":$title}}]
     + $sections
     + [{"type":"divider"},
        {"type":"context","elements":[{"type":"mrkdwn","text":$footer}]}]')

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

# ── Helper: Batch GitHub issue state check via GraphQL ──────────────
# Usage: gh_batch_states <input_tsv:repo<TAB>num> <output_tsv:repo<TAB>num<TAB>state<TAB>url>
# Uses GraphQL aliases — ~50 issues per API call. NOTFOUND = deleted/transferred/no access.
gh_batch_states() {
  local input="$1" out="$2"
  local tmpmap=/tmp/.gh-batch-map.$$
  : > "$out"; : > "$tmpmap"

  local chunk=50 i=0 query="" batch=0
  flush_batch() {
    [ -z "$query" ] && return
    local resp
    resp=$(gh api graphql -f query="query{$query}" 2>/dev/null)
    # Join alias results back to repo/num via map
    echo "$resp" | jq -r '.data // {} | to_entries[] | [.key, ((.value.issue.state)//"NOTFOUND"), ((.value.issue.url)//"")] | @tsv' \
      | awk -F'\t' -v map="$tmpmap" '
          BEGIN { while ((getline l < map) > 0) { split(l,a,"\t"); m[a[1]]=a[2]"\t"a[3] } }
          { print m[$1] "\t" $2 "\t" $3 }
        ' >> "$out"
    query=""; : > "$tmpmap"
  }

  while IFS=$'\t' read -r repo num; do
    [ -z "$repo" ] || [ -z "$num" ] && continue
    local owner="${repo%%/*}" name="${repo##*/}"
    local alias="i${i}"
    query+="  ${alias}: repository(owner:\"$owner\",name:\"$name\"){issue(number:$num){state url}}"$'\n'
    printf '%s\t%s\t%s\n' "$alias" "$repo" "$num" >> "$tmpmap"
    i=$((i+1)); batch=$((batch+1))
    if [ $batch -ge $chunk ]; then flush_batch; batch=0; fi
  done < "$input"
  flush_batch
  rm -f "$tmpmap"
}

# ── Helper: Upsert exactly ONE ClickUp-link bot comment on a GH issue ───
# Usage: gh_upsert_clickup_comment <owner/repo> <issue_num> <clickup_url> [pri] [sp] [domain]
#   pri:    1=Urgent 2=High 3=Normal 4=Low (omit → unknown)
#   sp:     story points integer (omit → ?)
#   domain: backend / frontend / mobile / etc. (omit → ?)
# Contract: one bot comment per issue. Updates if body changed, dedupes extras.
# Echoes: created | updated | nochange | deduped
gh_upsert_clickup_comment() {
  local repo="$1" num="$2" cu_url="$3" pri="${4:-}" sp="${5:-}" domain="${6:-}"
  local marker="<!-- pm-bot:clickup-link v1 -->"

  # Priority badge
  local pri_label
  case "$pri" in
    1) pri_label="🔴 Urgent" ;;
    2) pri_label="🟠 High"   ;;
    3) pri_label="🟡 Normal" ;;
    4) pri_label="⚪ Low"    ;;
    *) pri_label="—"         ;;
  esac

  local sp_label="${sp:-?}"
  [ "$sp_label" = "0" ] && sp_label="?"
  local domain_label="${domain:-?}"

  local body
  body="${marker}
📋 **Tracked in ClickUp:** ${cu_url}

| | |
|---|---|
| Priority | ${pri_label} |
| Story Points | ${sp_label} |
| Domain | ${domain_label} |

_Managed by CareSpace PM Bot — do not edit this comment._"

  # Fetch all bot comments on this issue (paginate in case of many)
  local comments
  comments=$(gh api "repos/$repo/issues/$num/comments" --paginate 2>/dev/null \
    | jq -s --arg m "$marker" '[.[] | .[] | select(.body | contains($m)) | {id, body}]')

  local count=$(echo "$comments" | jq 'length')
  local result="nochange"

  if [ "$count" = "0" ]; then
    gh api "repos/$repo/issues/$num/comments" -f body="$body" >/dev/null 2>&1 && result="created"
  else
    local first_id=$(echo "$comments" | jq -r '.[0].id')
    local first_body=$(echo "$comments" | jq -r '.[0].body')

    # Delete duplicates (keep first)
    if [ "$count" -gt 1 ]; then
      echo "$comments" | jq -r '.[1:][].id' | while read -r dup; do
        [ -n "$dup" ] && gh api -X DELETE "repos/$repo/issues/comments/$dup" >/dev/null 2>&1
      done
      result="deduped"
    fi

    # Update body if ClickUp URL changed or body drifted
    if [ "$first_body" != "$body" ]; then
      gh api -X PATCH "repos/$repo/issues/comments/$first_id" -f body="$body" >/dev/null 2>&1 && result="updated"
    fi
  fi
  echo "$result"
}

echo "PM context loaded — workspace $WORKSPACE_ID"
