---
name: pm-unassigned-alert
description: >
  Sprint unassigned member checker — finds all ClickUp team members with no
  assigned tasks in the active sprint and sends them a friendly Slack DM
  reminder. Use this skill when the user wants to check who on the team has
  no sprint tasks, send reminders to idle team members, audit sprint task
  coverage, or identify unassigned people in ClickUp. Triggers on: who has
  no tasks, unassigned members, send reminders to team, sprint coverage
  check, who is not working on anything, idle team members, dm people with
  no tasks.
---

# PM Unassigned Alert

**Fully autonomous. Read-only on ClickUp. Sends Slack DMs to members with zero assigned sprint tasks.**

## GUARDRAILS
- Read-only on ClickUp — NEVER creates, updates, or deletes tasks
- Only DMs people with **zero assigned tasks** in the active sprint
- ⛔ ONLY posts to channels in `$SLACK_ALLOWED_CHANNELS` — uses `slack_post()` guardrail from context.sh
- Audit summary goes to `$SLACK_STANDUP` (`#pm-standup`) — NEVER to any other channel
- Skips bots and deactivated Slack accounts
- Dry-run mode available: `DRY_RUN=true` — previews DMs without sending
- **ALL API responses go to /tmp files. Only read summaries into context.**

---

## SETUP

```bash
source ~/.claude/skills/_pm-shared/context.sh
echo "Workspace: $WORKSPACE_ID | Sprint folder: $FOLDER_SPRINTS | Token: ${CLICKUP_PERSONAL_TOKEN:0:8}..."
```

**Required env vars (all defined in context.sh):**
| Var | Value |
|---|---|
| `CLICKUP_PERSONAL_TOKEN` | ClickUp API token |
| `WORKSPACE_ID` | `31124097` |
| `FOLDER_SPRINTS` | `901317811717` |
| `SLACK_BOT_TOKEN` | Slack bot token (`users:read`, `users:read.email`, `im:write`, `chat:write`) |
| `SLACK_STANDUP` | `#pm-standup` |
| `DRY_RUN` | (optional) `true` to skip actual DM sends |

`cu_api()` and `slack_post()` helpers are loaded from context.sh — do not redefine them.

---

## EXECUTION

### Step 1: Find Active Sprint → /tmp/sprint-info.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

cu_api GET "folder/$FOLDER_SPRINTS/list" \
  | jq '[.lists[] | select(.status.status != "done")] | sort_by(.date_created) | last | {id, name, status: .status.status}' \
  > /tmp/sprint-info.json

SPRINT_ID=$(jq -r '.id // empty' /tmp/sprint-info.json)
SPRINT_NAME=$(jq -r '.name // empty' /tmp/sprint-info.json)
echo "Active sprint: $SPRINT_NAME (id: $SPRINT_ID)"

[ -z "$SPRINT_ID" ] && \
  slack_post "$SLACK_STANDUP" "Unassigned Check Skipped" "No active sprint found. Digest skipped." "pm-unassigned-alert" && \
  exit 0
```

---

### Step 2: Fetch All Sprint Tasks → /tmp/sprint-tasks.json

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_ID=$(jq -r '.id' /tmp/sprint-info.json)

cu_api GET "list/$SPRINT_ID/task?include_closed=true&subtasks=true" \
  | jq '[.tasks[] | {
      id,
      name: .name[0:60],
      status: .status.status,
      assignees: [.assignees[] | {id: (.id | tostring), username: .username, email: .email}]
    }]' > /tmp/sprint-tasks.json

echo "Total sprint tasks: $(jq length /tmp/sprint-tasks.json)"

# Extract unique assigned ClickUp user IDs (anyone with at least 1 task)
jq -r '[.[].assignees[].id] | unique[]' /tmp/sprint-tasks.json > /tmp/assigned-user-ids.txt
echo "Members with at least 1 task: $(wc -l < /tmp/assigned-user-ids.txt)"
cat /tmp/assigned-user-ids.txt
```

---

### Step 3: Fetch All ClickUp Team Members → /tmp/cu-members.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

cu_api GET "team/$WORKSPACE_ID/member" \
  | jq '[.members[] | {
      id: (.user.id | tostring),
      username: .user.username,
      email: .user.email,
      role: .user.role
    } | select(.role != null)]' \
  > /tmp/cu-members.json

echo "ClickUp members fetched: $(jq length /tmp/cu-members.json)"
jq -r '.[] | "  \(.id)  \(.username)  <\(.email)>"' /tmp/cu-members.json
```

> **Role reference:** `1`=Owner, `2`=Admin, `3`=Member, `4`=Guest
> To exclude guests, add `| select(.role != 4)` before the closing `]` in the jq filter.

---

### Step 4: Identify Members with Zero Assigned Tasks → /tmp/unassigned-members.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

ASSIGNED_IDS=$(jq -Rs '[split("\n")[] | select(length > 0)]' /tmp/assigned-user-ids.txt)

jq --argjson assigned "$ASSIGNED_IDS" \
  '[.[] | select(.id | IN($assigned[]) | not)]' \
  /tmp/cu-members.json > /tmp/unassigned-members.json

COUNT=$(jq length /tmp/unassigned-members.json)
echo "Members with NO assigned sprint tasks: $COUNT"
jq -r '.[] | "  • \(.username) (\(.email))"' /tmp/unassigned-members.json

if [ "$COUNT" -eq 0 ]; then
  slack_post "$SLACK_STANDUP" \
    "✅ Full Sprint Coverage — $(jq -r '.name' /tmp/sprint-info.json)" \
    "All team members have at least one task assigned this sprint. No reminders needed." \
    "pm-unassigned-alert"
  exit 0
fi
```

---

### Step 5: Fetch Slack User Directory → /tmp/slack-users.json

```bash
source ~/.claude/skills/_pm-shared/context.sh

curl -s "https://slack.com/api/users.list" \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  | jq '[.members[]
      | select(.deleted == false)
      | select(.is_bot == false)
      | select(.id != "USLACKBOT")
      | {
          slack_id: .id,
          real_name: .real_name,
          display_name: .profile.display_name,
          email: .profile.email
        }]' > /tmp/slack-users.json

echo "Active Slack users: $(jq length /tmp/slack-users.json)"
```

---

### Step 6: Match Unassigned CU Members → Slack IDs → /tmp/match-results.json

Match strategy: **email → Slack user ID** (most reliable, same identity provider).

```bash
source ~/.claude/skills/_pm-shared/context.sh

# Build email→slack_id lookup from Slack directory
jq 'map({(.email // ""): .slack_id}) | add // {}' /tmp/slack-users.json > /tmp/slack-email-map.json

# Match each unassigned CU member to their Slack ID
jq --slurpfile slack_map /tmp/slack-email-map.json \
  '[.[] | {
    cu_username: .username,
    email: .email,
    slack_id: ($slack_map[0][.email] // null)
  }]' /tmp/unassigned-members.json > /tmp/match-results.json

echo "Match results:"
jq -r '.[] | "  \(.cu_username) (\(.email)) → Slack: \(.slack_id // "NOT FOUND")"' /tmp/match-results.json

jq '[.[] | select(.slack_id != null)]' /tmp/match-results.json > /tmp/matched.json
jq '[.[] | select(.slack_id == null)]' /tmp/match-results.json > /tmp/unmatched.json

echo "Will DM: $(jq length /tmp/matched.json) | No Slack match: $(jq length /tmp/unmatched.json)"
```

---

### Step 7: Send Friendly DM to Each Unassigned Member

DMs go **directly to the Slack user ID** — `chat.postMessage` with a user ID opens their DM automatically.

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)
DRY_RUN=${DRY_RUN:-false}

> /tmp/dm-log.txt

while IFS= read -r row; do
  SLACK_ID=$(echo "$row" | jq -r '.slack_id')
  NAME=$(echo    "$row" | jq -r '.cu_username')

  MSG="Hey ${NAME}! 👋 Just a friendly heads-up — it looks like you don't have any tasks assigned in *${SPRINT_NAME}* yet.\n\nIf you're already working on something, please make sure it's logged in ClickUp so the team can see your progress. If you have capacity, have a look at the backlog and grab something! 🚀\n\nLet me know if you need any help. — PM Bot"

  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY RUN] → Would DM $NAME ($SLACK_ID)" | tee -a /tmp/dm-log.txt
    echo "           Msg: $MSG"                    | tee -a /tmp/dm-log.txt
  else
    RESULT=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
      -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg ch  "$SLACK_ID" \
        --arg txt "$MSG" \
        '{channel: $ch, text: $txt}')" | jq -r '.ok // "false"')
    echo "DM → $NAME ($SLACK_ID): $RESULT" | tee -a /tmp/dm-log.txt
  fi

done < <(jq -c '.[]' /tmp/matched.json)

echo "---"
cat /tmp/dm-log.txt
```

> Members found in ClickUp but with no matching Slack account are listed in the audit summary (Step 8) — no DM sent, no crash.

---

### Step 8: Post Audit Summary → $SLACK_STANDUP (#pm-standup)

Uses `slack_post()` from context.sh — idempotent (updates today's existing message if already posted).

```bash
source ~/.claude/skills/_pm-shared/context.sh
SPRINT_NAME=$(jq -r '.name' /tmp/sprint-info.json)

TOTAL_CU=$(jq length /tmp/cu-members.json)
TOTAL_ASSIGNED=$(wc -l < /tmp/assigned-user-ids.txt | tr -d ' ')
TOTAL_UNASSIGNED=$(jq length /tmp/unassigned-members.json)

REMINDED_LIST=$(jq -r '.[] | "• \(.cu_username)"' /tmp/matched.json   2>/dev/null || echo "_none_")
UNMATCHED_LIST=$(jq -r '.[] | "• \(.cu_username) (\(.email))"' /tmp/unmatched.json 2>/dev/null || echo "_none_")

DRY_NOTE=""
[ "${DRY_RUN:-false}" = "true" ] && DRY_NOTE="\n⚠️ _DRY RUN — no DMs were actually sent._"

BODY="*Sprint:* $SPRINT_NAME
*Team:* $TOTAL_CU members | $TOTAL_ASSIGNED with tasks | $TOTAL_UNASSIGNED with no tasks

*📨 DM reminders sent to:*
$REMINDED_LIST

*⚠️ In ClickUp but no Slack account found (no DM sent):*
$UNMATCHED_LIST
$DRY_NOTE"

slack_post "$SLACK_STANDUP" \
  "🔔 Sprint Unassigned Check — $SPRINT_NAME" \
  "$BODY" \
  "pm-unassigned-alert"
```

---

## EDGE CASES

| Situation | Behaviour |
|---|---|
| No active sprint | `slack_post` skip notice to `$SLACK_STANDUP`, stop |
| All members assigned | `slack_post` ✅ confirmation to `$SLACK_STANDUP`, stop |
| Member in ClickUp but not Slack | Listed in audit summary, no DM sent |
| `DRY_RUN=true` | All steps run, no DMs sent, audit marked as dry run |
| Guests (role 4) | Included by default; add `select(.role != 4)` in Step 3 to exclude |
| Member assigned only to closed tasks | Still counted as assigned (contributed this sprint) |
| Unauthorized Slack channel | `slack_post()` guardrail in context.sh blocks and logs — never posts outside approved channels |

---

## CUSTOMISING THE DM MESSAGE

Edit the `MSG=` block in Step 7. Available variables:
- `$NAME` — ClickUp username
- `$SPRINT_NAME` — current active sprint name
- Slack mrkdwn: `*bold*`, `_italic_`, `\n` for newlines, `<https://url|label>` for links
