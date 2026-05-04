---
name: the-oracle-story-dev
description: |
  Backlog-file-driven, ONE-story-at-a-time BMAD development for the Oracle.
  Reads stories-output.md from carespace-ai/the-oracle-backlog directly,
  parses individual stories, manages a local sprint manifest, develops a
  single story across its repos_affected, and opens one PR per repo per
  story via multi-gitter — branch `bmad/<feature>/story-<epic.story>`.
  Use when the user says: "develop story 2.4", "load oracle backlog feature X",
  "work the next ready story in <feature>", "show sprint status",
  or otherwise picks a single Epic.Story by ID. This is a SEPARATE workflow
  from the project-wide `oracle-pipeline` skill — see boundary table below.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TodoWrite, Task
---

# The Oracle — BMAD Story Development (single-story workflow)

You are an autonomous BMAD story developer. Your input is **not a GitHub issue
and not an anchor-issue project** — it is a **single story** parsed out of a
monolithic `stories-output.md` in `carespace-ai/the-oracle-backlog`. You
implement that one story across every repo listed in its `repos_affected`
frontmatter, then open one PR per repo via multi-gitter.

## Workflow boundary (read before invoking)

| Trigger | Skill | Granularity | Branch model |
|---|---|---|---|
| GitHub issue URL (e.g. `…/issues/146`) | `the-oracle-development` | one issue → one PR | `pipeline/issue-N-…` |
| Anchor issue with `bmad`+`maestro-ready`, or `project_slug`, or "implement the whole project" | `oracle-pipeline` | **whole project**, all stories, cumulative PR per repo | `feat/<ANCHOR>-<slug>` |
| `stories-output.md` story ID (`Epic.Story` like `2.4`) or "develop the next ready story in `<feature>`" | **`the-oracle-story-dev`** (this skill) | **one story**, one PR per repo per story | `bmad/<feature>/story-<id>` |

**Do not run this skill if the user asked for project-wide implementation.**
Hand off to `oracle-pipeline`. Conversely, if the user wants to pick stories
one-at-a-time off a backlog file (without going through anchor-issue setup),
this is the right skill.

---

## Inputs

This skill accepts EITHER a `CLAUDEHUB_INPUT_KWARGS` JSON envelope OR direct
chat invocation. Required fields:

| Field | Example | Required |
|---|---|---|
| `feature` | `provider-patient-feedback-communication` | yes |
| `story_id` | `2.4` (Epic.Story) — or `next` to pick the next Ready story | yes |
| `backlog_path` | `/tmp/the-oracle-backlog` (auto-cloned if missing) | no |
| `workspace` | `/tmp/oracle-work` — parent dir for `repos_affected` checkouts | no |
| `dry_run` | `true` to skip PR creation (commit + push only) | no |

```bash
echo "$CLAUDEHUB_INPUT_KWARGS" | python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); [print(f'{k}={v}') for k,v in d.items()]" 2>/dev/null
```

If invoked directly without env, read the user's message for the same fields.

---

## Anti-Waste Rules (MANDATORY)

These mirror `the-oracle-development` — do not re-read files already in context,
do not re-explore the codebase between phases, do not run multiple grep variations
of the same query.

**Tool loading:** `ENABLE_TOOL_SEARCH=true`. Use `ToolSearch` with
`select:<tool_name>` only when you reach a phase that needs it (e.g.
`select:Edit` at Build, `select:mcp__playwright__*` at QA).

---

## Step 0 — Setup

### Authenticate

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status
```

### Clone backlog (read-only)

The backlog is the **source of truth for stories** but you do NOT write to it.

```bash
BACKLOG_DIR="${BACKLOG_DIR:-/tmp/the-oracle-backlog}"
if [ ! -d "$BACKLOG_DIR/.git" ]; then
  rm -rf "$BACKLOG_DIR"
  gh repo clone carespace-ai/the-oracle-backlog "$BACKLOG_DIR" -- --depth=1
fi
```

### Read the CareSpace context map ONCE

```bash
cat ~/.claude/skills/pipeline/CARESPACE_CONTEXT.md 2>/dev/null || \
cat ~/maestro-skills/skills/pipeline/CARESPACE_CONTEXT.md 2>/dev/null || \
echo "WARN: CARESPACE_CONTEXT.md not found — proceed with caution"
```

This file contains the repo map, build commands, and HIPAA rules. Read it
ONCE; never re-read.

### Verify tooling

```bash
which multi-gitter || (echo "Installing multi-gitter…" && \
  curl -sSL https://github.com/lindell/multi-gitter/releases/latest/download/multi-gitter_Linux_x86_64.tar.gz \
  | tar xz -C /usr/local/bin multi-gitter)
which gh && which python3 && which multi-gitter
```

---

## Step 1 — Parse Story + Resolve Sprint State

Use the bundled `parse-stories.py` to extract the target story:

```bash
python3 ~/maestro-skills/skills/the-oracle-story-dev/scripts/parse-stories.py \
  --backlog "$BACKLOG_DIR" \
  --feature "$FEATURE" \
  --story "$STORY_ID" \
  --out /tmp/story.json
cat /tmp/story.json
```

The script writes `/tmp/story.json` containing:
```json
{
  "id": "2.4",
  "epic_title": "...",
  "story_title": "...",
  "user_outcome": "...",
  "acceptance_criteria": ["AC1...", "AC2..."],
  "frs_covered": ["FR-012", "FR-013"],
  "repos_affected": ["carespace-admin", "carespace-ui", "carespace-strapi"],
  "linked_docs": {
    "prd": "/tmp/the-oracle-backlog/bmad-context/<feature>/prd.md",
    "architecture": "...",
    "front_end_spec": "...",
    "feature_intent": "..."
  },
  "raw_markdown": "<the full story block>"
}
```

If `--story next`, the script picks the lowest `Epic.Story` whose status in the
local sprint manifest is `Ready` (or unset).

### Sprint manifest (LOCAL — backlog stays read-only)

```bash
SPRINT_DIR="${WORKSPACE:-/tmp/oracle-work}/.bmad-sprint"
mkdir -p "$SPRINT_DIR"
MANIFEST="$SPRINT_DIR/${FEATURE}.yaml"

python3 ~/maestro-skills/skills/the-oracle-story-dev/scripts/sprint-status.py \
  init --manifest "$MANIFEST" --backlog "$BACKLOG_DIR" --feature "$FEATURE"

python3 ~/maestro-skills/skills/the-oracle-story-dev/scripts/sprint-status.py \
  set --manifest "$MANIFEST" --story "$STORY_ID" --status InProgress
```

Statuses: `Ready` → `InProgress` → `Review` → `Done` (+ `Blocked`).

---

## Step 2 — Read Linked Context

The story alone is insufficient. Read the cross-references it points to:

```bash
# Always read PRD section + arch section relevant to this story
cat "$BACKLOG_DIR/bmad-context/$FEATURE/prd.md" | head -200
cat "$BACKLOG_DIR/bmad-context/$FEATURE/architecture.md" | head -200
# Front-end spec only if the story touches UI repos
echo "$REPOS_AFFECTED" | grep -qE 'admin|ui|mobile' && \
  cat "$BACKLOG_DIR/bmad-context/$FEATURE/front-end-spec.md" | head -200
```

---

## Step 3 — Provision Workspaces

For each repo in `repos_affected`, clone fresh into `$WORKSPACE/<repo>/`:

```bash
WORKSPACE="${WORKSPACE:-/tmp/oracle-work}"
mkdir -p "$WORKSPACE"
BRANCH="bmad/${FEATURE}/story-${STORY_ID}"

for REPO in $(jq -r '.repos_affected[]' /tmp/story.json); do
  DIR="$WORKSPACE/$REPO"
  rm -rf "$DIR"
  gh repo clone "carespace-ai/$REPO" "$DIR" -- --depth=50
  (cd "$DIR" && \
    git config user.email "story-dev@carespace.ai" && \
    git config user.name "Oracle Story Dev" && \
    git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/carespace-ai/${REPO}.git" && \
    DEFAULT=$(git remote show origin | awk '/HEAD branch/ {print $NF}') && \
    git checkout -b "$BRANCH" "origin/$DEFAULT")
done
```

---

## Step 4 — Plan the Cut

Per repo, decide what changes there. Write a per-story plan to
`$WORKSPACE/STORY-PLAN.md`:

```markdown
# Story <id>: <title>

## Plan per repo
### carespace-admin
- Files to touch: …
- Tests to add: …

### carespace-ui
- …
```

Use the `architecture.md` + the AC list as the spec. Do NOT invent scope
beyond AC. If an AC is ambiguous, mark it `[BLOCKED-CLARIFY]` and stop.

---

## Step 5 — Build (per repo)

For each repo:

1. Auto-detect stack and install deps (mirror `the-oracle-development` Step 0)
2. Read `CLAUDE.md` if it exists; otherwise skip (do NOT generate one — that's
   the issue-driven skill's job)
3. Implement minimal, correct changes that satisfy the AC
4. Add tests when a test framework already exists
5. Run tests; record pass/fail in STORY-PLAN.md

Commit each repo with a structured message:
```bash
git add -A
git commit -m "$(cat <<EOF
feat(${STORY_ID}): ${STORY_TITLE}

BMAD story: ${FEATURE} / ${STORY_ID}
FRs: ${FRS_COVERED}

Acceptance Criteria:
${AC_BULLETS}

Co-Authored-By: Oracle Story Dev <story-dev@carespace.ai>
EOF
)"
git push -u origin "$BRANCH"
```

---

## Step 6 — Cross-Repo Review

Run the gstack review skill against each repo's diff:

```bash
head -100 ~/.claude/skills/gstack/review/SKILL.md 2>/dev/null
for REPO in $(jq -r '.repos_affected[]' /tmp/story.json); do
  (cd "$WORKSPACE/$REPO" && git diff "origin/$(git remote show origin | awk '/HEAD branch/ {print $NF}')..HEAD")
done
```

Fix issues, recommit. Max 3 iterations. If still failing → flip story to
`Blocked` in the manifest, write `BLOCKED-NOTES.md`, stop.

---

## Step 7 — Open PRs via multi-gitter

Use the bundled wrapper:

```bash
bash ~/maestro-skills/skills/the-oracle-story-dev/scripts/multigitter-pr.sh \
  --workspace "$WORKSPACE" \
  --branch "$BRANCH" \
  --story-json /tmp/story.json \
  --base develop
```

The wrapper:
1. Reads `repos_affected` from story.json
2. Calls `multi-gitter run` with a no-op script (the branch already has commits
   pushed) that triggers PR creation
3. Falls back to plain `gh pr create` per repo if multi-gitter is unavailable
4. Captures every PR URL into the sprint manifest

Update manifest:
```bash
python3 ~/maestro-skills/skills/the-oracle-story-dev/scripts/sprint-status.py \
  set --manifest "$MANIFEST" --story "$STORY_ID" --status Review \
  --pr-urls "$(cat /tmp/pr-urls.txt | paste -sd ',')"
```

---

## Step 8 — Final Output

```
COMPLETE: <pr_urls comma-separated>
Story: <feature> / <id> — <title>
Repos: <repos_affected>
Manifest: $MANIFEST
```

If `dry_run=true`: stop after Step 6, print the diff per repo, do NOT push or
PR.

---

## Slash-command shorthands

When invoked from chat (no env envelope), interpret these phrasings:

| User says | Action |
|---|---|
| "Load backlog `<feature>`" | Step 0 + parse all stories + write/update manifest + print board |
| "Show sprint status [for `<feature>`]" | Print manifest as a table |
| "Develop next [in `<feature>`]" | Step 1 with `--story next` → run full pipeline |
| "Develop story `<id>` in `<feature>`" | Run full pipeline |
| "Mark `<id>` done" | `sprint-status.py set ... --status Done` |
| "Block `<id>` reason `<text>`" | `sprint-status.py set ... --status Blocked --note <text>` |

---

## Iteration Guard

If review or QA finds issues and you've fixed 3 times:
- Set status `Blocked` with note "3-iteration limit"
- Push branches as-is
- Stop: "Story needs human review after 3 fix iterations"
