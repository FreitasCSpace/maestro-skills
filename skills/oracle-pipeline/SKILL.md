---
name: oracle-pipeline
description: |
  Autonomous project-level dev pipeline — implements an entire Oracle backlog
  project (all epics + all user stories) in one session.
  Triggered by user-story issues in `the-oracle-backlog` that share a
  `project:<name>` label and carry `maestro-ready`. Consumes the project's
  BMAD context, iterates every story in dependency order, opens one cumulative
  PR per affected repo, and fires a `repository_dispatch` event to deploy the
  ephemeral review env.
---

# Oracle Pipeline (project-level)

You are an autonomous **project-level** development pipeline. The unit of work
is an entire Oracle backlog project: every epic and every user story sharing
a `project:<name>` label, executed in BMAD-defined dependency order, in a
single session. There is NO per-story human gate.

## Trigger model — uses existing `project:*` labels (no `project-meta` label)

The backlog uses `project:<name>` labels on user-story issues to group them.
There is no separate `project-meta` issue and no `project-meta` label. This
skill treats the **set of open user-story issues** sharing a `project:<X>`
label and carrying `maestro-ready` as the project's trigger surface.

Within a project group, the **anchor issue** is the lowest-numbered open user
story in the group. All orchestration comments (status, completion, failure)
go on the anchor issue. The other user-stories in the group are still
updated with status labels as they are implemented.

This skill is a project-level adaptation of the original `pipeline` skill.
Differences vs `pipeline/` at a glance:

| `pipeline/`                     | `oracle-pipeline/` (this skill)            |
|---------------------------------|--------------------------------------------|
| Trigger: single GitHub issue    | Trigger: `project:<X>` + `maestro-ready` user-story group |
| Clones one repo                 | Clones every repo in `feature_intent.involved_repos` |
| gstack loop runs ONCE for the issue | gstack loop (Investigate → Think → Plan → Build → Review → Security → QA) runs **per story**, scoped to that story's affected_modules |
| One commit, one PR              | Atomic commit per story, one cumulative PR per affected repo |
| Branch: `pipeline/issue-N-...`  | Branch: `feat/oracle-project-<slug>` per repo |
| Targets `develop`               | Targets `main`, labeled `oracle-project`, `group:project-<slug>`, original `project:` label |
| No scope guardrail              | Per-story scope guardrail + cumulative scope audit |
| No structured output            | Emits `oracle.project.complete` JSON event via `repository_dispatch` to `carespace-ai/infra` |

**CRITICAL FIRST STEP — DO THIS BEFORE ANYTHING ELSE:**

Any files in the current working directory are STALE from a previous pipeline
run. Do NOT read them. Do NOT look at PIPELINE.md. Do NOT assume any work is
done. This is a BRAND NEW project run. Ignore everything in the current
directory.

Your very first action must be Step 0.0 (input gate) below. NEVER say
"already completed" — every run is a new project.

---

## Tool Loading Strategy (saves context)

This session runs with `ENABLE_TOOL_SEARCH=true`. Tools and skills are NOT
pre-loaded into context. Use `ToolSearch` to load tools when you need them.

**Only load tools/skills for the phase you're currently executing.**

- Setup phase: you already have Bash, Read, Write — no ToolSearch needed
- Per-story build: `ToolSearch` with `"select:Edit,Grep,Glob"` when you first need them
- QA phase: `ToolSearch` for `"browser playwright"` only if visual testing is needed

---

## CareSpace Codebase Context (DEFERRED — read after Phase 0.5)

`~/.claude/skills/oracle-pipeline/CARESPACE_CONTEXT.md` is ~47KB. Reading
the whole file up front blows the context budget on information for repos
the current project doesn't touch. **Do NOT `cat` it at startup.**

The read is deferred to **Phase 0.5b** (after BMAD context loads and
`involved_repos` is known), and is **scoped to only the relevant repo
sections**. See Phase 0.5b below.

When you do read the scoped extract, use it to:

1. **Match each target repo to its Repository Map row** — stack, default
   branch, build commands.
2. **Use the per-repo "Where to look by issue type" tables** to jump
   directly to the relevant folder for each story's affected modules.
3. **Check the HIPAA notes** before touching any file that handles PHI
   (Profile, Client, Evaluation, Survey, etc).

You read the scoped extract ONCE per project run. Never re-read.

---

## Anti-Waste Rules (MANDATORY)

### 1. Never re-read a file you already read
Once read, the file is in your context. Don't re-read unless modified or the
user asks. Applies to:
- `context-scoped.md` (built once in Phase 0.5b, read ONCE)
- `CARESPACE_CONTEXT.md` full file — DO NOT read; use the scoped extract
- The anchor issue body (`gh issue view` ONCE)
- `feature-intent.json`, `stories-output.md`, `architecture.md`, `prd.md`,
  `front-end-spec.md` (read ONCE at start)
- `PIPELINE.md` after you wrote to it
- Source files you've already inspected

### 2. Never re-read PIPELINE.md unless you wrote to it
PIPELINE.md is YOUR memory of the run. You wrote it. You know what's in it.

### 3. Never re-explore the codebase between stories
Files relevant to story N.M are listed in the story's `affected_modules` and
`new_files_needed`. Use them — don't re-grep / re-find.

### 4. Use the BMAD context, not blind exploration
For every file: did `feature-intent.json` or the story already tell me about
this? If yes, go directly. If no, grep first.

### 5. One search per question
Don't run 3 grep variations. Pick the best one. One alternative — then move on.

### 6. Scan stops the moment you find a project to run
The auto-discovery query in 0.0 is bounded — exactly ONE `gh issue list`
call. Do not wander the issue list looking for a meta issue, an epic issue,
or anything else. The contract is: `project:<X>` + `user-story` +
`maestro-ready` + open. Nothing else.

---

## Step 0 — Setup

### 0.0 Input gate (do this FIRST, before anything else)

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Two valid input modes:

**Mode A — orchestrator-driven (preferred).** `$CLAUDEHUB_INPUT_KWARGS` is a
JSON object containing at minimum `project_slug`. Example:

```json
{
  "project_slug": "asset-management-system-ams",
  "target_org": "carespace-ai",
  "anchor_issue_number": 286
}
```

`anchor_issue_number` is optional; if omitted it is resolved in 0.4.

**Mode B — manual / auto-discovery.** Input is empty. The skill resolves
`project_slug` itself by listing eligible projects (0.1).

In BOTH modes, `target_org` defaults to `carespace-ai`. `$GITHUB_TOKEN` must
be set (the Maestro AI GitHub App installation token).

If `$GITHUB_TOKEN` is empty: print `BLOCKED: GITHUB_TOKEN missing` and exit
1. Do not improvise.

If neither Mode A nor Mode B can resolve a `project_slug` after 0.1: print
`BLOCKED: no eligible project found (no open user-story issues with project:*
+ maestro-ready labels)` and exit 1. Do not improvise. Do not try
alternative label names.

### 0.1 Resolve project_slug if not provided

```bash
gh auth status >/dev/null || { echo "BLOCKED: GITHUB_TOKEN invalid"; exit 1; }

if [ -z "$PROJECT_SLUG" ]; then
  # Mode B: discover eligible projects
  ELIGIBLE=$(gh issue list \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --label maestro-ready --label user-story \
    --state open --limit 1000 \
    --json number,labels \
    | jq -r '
      [.[] | .labels[] | select(.name | startswith("project:"))]
      | group_by(.name) | map({label: .[0].name, count: length})
      | sort_by(-.count) | .[]
      | "\(.count)\t\(.label)"
    ')

  if [ -z "$ELIGIBLE" ]; then
    echo "BLOCKED: no eligible project found"; exit 1
  fi

  # Pick the project with the most ready stories. Slugify its label.
  TOP_LABEL=$(echo "$ELIGIBLE" | head -1 | cut -f2- | sed 's/^project: //')
  PROJECT_SLUG=$(echo "$TOP_LABEL" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
  echo "Auto-selected project: $TOP_LABEL → slug=$PROJECT_SLUG"
fi

# Re-derive the canonical "project:<X>" label string for queries below
# (the slug is for branches and dirs; the label is for issue searches)
PROJECT_LABEL="project:${TOP_LABEL:-$PROJECT_SLUG_TITLE}"
```

If the orchestrator passed `project_slug` but not the label string, derive
the label by listing labels matching `project:*` and selecting the one whose
slugified value matches `$PROJECT_SLUG`. If none match, exit 1 with
`BLOCKED: no project label matches slug '$PROJECT_SLUG'`.

### 0.2 Wipe and prepare workspace

```bash
rm -rf /tmp/oracle-work 2>/dev/null
mkdir -p /tmp/oracle-work /tmp/oracle-work/workspace
cd /tmp/oracle-work
```

**You MUST work in `/tmp/oracle-work` for the entire run.**

### 0.3 List the project's user-story issues (the trigger surface)

```bash
gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label "$PROJECT_LABEL" --label maestro-ready --label user-story \
  --state open --limit 1000 \
  --json number,title,labels,body \
  > /tmp/oracle-work/stories.json

STORY_COUNT=$(jq length /tmp/oracle-work/stories.json)
[ "$STORY_COUNT" -gt 0 ] || { echo "BLOCKED: no user-story issues with $PROJECT_LABEL + maestro-ready"; exit 1; }
```

These issues are the **trigger surface** — they are NOT the implementation
contract. The implementation contract lives in `bmad-context/<slug>/`.

### 0.4 Resolve anchor issue

The anchor issue is the lowest-numbered open user-story in the project group.
All orchestration comments go here.

```bash
ANCHOR_ISSUE=$(jq -r '[.[] | .number] | min' /tmp/oracle-work/stories.json)
```

If the orchestrator provided `anchor_issue_number`, use that instead — but
verify it appears in `stories.json`; if not, exit 1.

### 0.5 Load and validate BMAD context

```bash
gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- --depth=1
CTX_DIR="backlog/bmad-context/$PROJECT_SLUG"
cd "$CTX_DIR" 2>/dev/null || {
  gh issue comment "$ANCHOR_ISSUE" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context dir not found at \`bmad-context/$PROJECT_SLUG/\` — pipeline cannot run"
  exit 1
}

REQUIRED=(feature-intent.json architecture.md prd.md front-end-spec.md stories-output.md)
MISSING=()
for f in "${REQUIRED[@]}"; do
  [ -f "$f" ] || MISSING+=("$f")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  gh issue comment "$ANCHOR_ISSUE" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context incomplete: missing ${MISSING[*]}"
  # Strip maestro-ready from the entire group (not just anchor)
  jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
    gh issue edit "$n" --repo "$TARGET_ORG/the-oracle-backlog" --remove-label maestro-ready
  done
  exit 1
fi
cd /tmp/oracle-work
```

Then **read all five files ONCE** into context. Extract:
- `involved_repos[].full_name` from `feature-intent.json`
- The dependency-ordered story list from `stories-output.md`
  (Epic 1: 1.1, 1.2, …; Epic 2: 2.1, 2.2, …)
- Per-story `affected_modules`, `new_files_needed`, `dev_notes`,
  `acceptance_criteria`

The story IDs in `stories-output.md` are the BMAD ordering source. The
GitHub user-story issues from 0.3 are matched to them by title text or by
an explicit `story:N.M` label if BMAD writes one. If neither matches: log a
warning to PIPELINE.md but proceed using the BMAD ordering.

### 0.5b Read CARESPACE_CONTEXT scoped to involved_repos

Now that `involved_repos` is known, extract ONLY the sections of
`CARESPACE_CONTEXT.md` matching those repos plus the always-needed
top-of-file architecture overview. Skip everything else.

```bash
CTX=~/.claude/skills/oracle-pipeline/CARESPACE_CONTEXT.md
SCOPED=/tmp/oracle-work/context-scoped.md

# Always include the prologue (everything before the first per-repo section)
awk '/^## carespace-/{exit} {print}' "$CTX" > "$SCOPED"

# Append each involved repo's section (## carespace-X up to the next ## carespace-)
for REPO in "${INVOLVED_REPOS[@]}"; do
  awk -v r="## $REPO" '
    $0 ~ "^"r" " || $0 == r {p=1}
    p && /^## carespace-/ && $0 !~ "^"r" " && $0 != r {p=0}
    p {print}
  ' "$CTX" >> "$SCOPED"
done

wc -c "$SCOPED"  # expect ~5–10KB instead of 47KB
cat "$SCOPED"
```

Read the scoped output ONCE. Do NOT read the full
`CARESPACE_CONTEXT.md` — the extract is sufficient and the full file
will exhaust the context budget on irrelevant repos.

If `wc -c` on the scoped extract is < 1000 bytes, the awk match probably
failed (repo names in `involved_repos` don't match the `## carespace-X`
section headers). In that case, fall back to reading the full file via
the Read tool — but only as a recovery path, not the default.

### 0.6 Acquire concurrency slot

A project is "active" if any of its user-stories carry `oracle:implementing`.

```bash
ACTIVE=$(gh issue list \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --label oracle:implementing --state open --limit 1000 \
  --json labels \
  | jq '[.[] | .labels[] | select(.name | startswith("project:")) | .name] | unique | length')

if [ "$ACTIVE" -ge 2 ]; then
  echo "Concurrency cap reached ($ACTIVE active projects); leaving maestro-ready in place"
  exit 0
fi

# Mark every user-story in the group as implementing
jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
  gh issue edit "$n" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --add-label oracle:implementing \
    --remove-label maestro-ready
done

gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Oracle pipeline started for \`$PROJECT_LABEL\` ($STORY_COUNT user-stories). Tracking on this issue."
```

### 0.7 Clone every involved repo

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  gh repo clone "$TARGET_ORG/$REPO" "workspace/$REPO" -- --depth=50
  cd "workspace/$REPO"
  git fetch --unshallow 2>/dev/null || true
  git config user.email "oracle-pipeline@carespace.ai"
  git config user.name "Oracle Pipeline"
  git remote set-url origin \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET_ORG}/${REPO}.git"
  cd /tmp/oracle-work
done
```

### 0.8 Create or reset the project branch (idempotent)

```bash
BRANCH="feat/oracle-project-$PROJECT_SLUG"
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  git fetch origin main "$BRANCH" 2>/dev/null || git fetch origin main

  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    NON_AI=$(git log "origin/main..origin/$BRANCH" \
      --pretty='%ae' | grep -v '^oracle-pipeline@carespace\.ai$' | head -1)
    if [ -n "$NON_AI" ]; then
      gh issue comment "$ANCHOR_ISSUE" \
        --repo "$TARGET_ORG/the-oracle-backlog" \
        --body "Human commits detected on AI project branch in \`$REPO\` — manual reconciliation required"
      exit 1
    fi
    git checkout -B "$BRANCH" origin/main
  else
    git checkout -B "$BRANCH" origin/main
  fi
  cd /tmp/oracle-work
done
```

### 0.9 Auto-detect stack and install per repo

Same logic as the original `pipeline` skill, but run for each cloned repo.
Detection in priority order: `package-lock.json` → `yarn.lock` → `bun.lock` →
`package.json` → `build.gradle*` → `go.mod` → `requirements.txt` →
`pyproject.toml` → `pubspec.yaml` → `Gemfile`.

Generate a temporary `CLAUDE.md` per repo if missing (same template as
`pipeline/`). Do NOT commit a generated `CLAUDE.md` on the project branch.

### 0.10 Write the master PIPELINE.md

At `/tmp/oracle-work/PIPELINE.md`:

```markdown
# Oracle Project Pipeline Run

## Project
slug: <project-slug>
label: <project:X>
anchor-issue: <org>/the-oracle-backlog#<N>
group user-stories: <list of issue numbers>
involved repos: <list>
total stories (BMAD): <N>

## BMAD Context
- feature-intent.json: <key fields summary>
- stories-output.md: <epic/story counts>

## Status
IN_PROGRESS

## Story Log
(filled per story below)
```

PIPELINE.md is your run-memory. It is NOT committed to any repo — it lives
only in `/tmp/oracle-work/`.

---

## Phase 0.5 — Bootstrap Tests (per repo, only if missing)

Before the story loop starts, for each cloned repo check whether a test
suite exists. If not, bootstrap one — same logic as `pipeline/` Phase 3.5
(detect framework, add minimal config, smoke-test imports). This runs ONCE
at project start, not per story.

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  TEST_FILES=$(find . -type f \( -name "*.test.*" -o -name "*.spec.*" \
    -o -name "*_test.*" -o -name "test_*" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -1)
  if [ -z "$TEST_FILES" ]; then
    # Bootstrap per stack — see pipeline/SKILL.md Phase 3.5 for full logic
    # (Jest for Node, pytest for Python, etc.). Add minimal config + smoke test.
    git add -A && git commit -m "[Bootstrap] add test scaffold for project run"
  fi
  cd /tmp/oracle-work
done
```

Append `## Test Bootstrap` to PIPELINE.md noting which repos were
bootstrapped. The bootstrap commit is part of the cumulative diff but is
exempt from the per-story scope guardrail (it's foundational, not story
work).

---

## Phase 1 — Story Iteration with full gstack loop

This is the project-level analog of `pipeline/` Phases 1–7. For each story
in BMAD dependency order (from `stories-output.md`), execute the full
gstack pipeline scoped to **that one story** across the repos it touches.
Each story is its own mini-pipeline run inside the project run.

The gstack methodology is authoritative — `pipeline/` reads each
`~/.claude/skills/gstack/<phase>/SKILL.md` head-100 at runtime. **Do the
same here, per story.** Don't paraphrase the gstack instructions — read
and follow them.

### Per-story loop

```
for story in stories_output.md (in BMAD order):
    cd /tmp/oracle-work
    SCOPE = story.affected_modules ∪ story.new_files_needed
    REPOS = repos touched by SCOPE  (a subset of involved_repos)
    Append `### Story <N.M> — <title>` to PIPELINE.md with `## Status: IN_PROGRESS`

    1.1  Investigate (gstack/investigate)
         head -100 ~/.claude/skills/gstack/investigate/SKILL.md
         For each repo in REPOS: cd workspace/<repo>, follow gstack
         investigate methodology BUT scoped to story.affected_modules —
         do NOT explore beyond SCOPE. Record root cause / approach in
         PIPELINE.md `## Investigation` for this story.

    1.2  Think (gstack/office-hours)
         head -100 ~/.claude/skills/gstack/office-hours/SKILL.md
         Apply the six forcing questions to the story's acceptance
         criteria. Append `## Think` to the story's PIPELINE.md section.

    1.3  Plan (gstack/plan-eng-review)
         head -100 ~/.claude/skills/gstack/plan-eng-review/SKILL.md
         Lock the per-repo edit plan. Verify every planned file is in
         SCOPE — if a planned file is outside SCOPE, either drop it or
         flag it as a scope deviation now (don't discover it post-build).
         Append `## Plan` to the story section.

    1.4  Build
         For each repo in REPOS:
           cd workspace/<repo>
           Apply the plan via Edit / Write
           Run the project's test command (from CLAUDE.md)
           If tests fail and fixable inline: fix and re-run
             (max 2 inline fix attempts per story per repo)
         Capture diff vs HEAD: every modified path MUST be in SCOPE.
         Out-of-scope paths → append to project scope_deviations[] (do
         NOT block the story).

    1.5  Review (gstack/review)
         head -100 ~/.claude/skills/gstack/review/SKILL.md
         Run the gstack review loop on the per-story diff (NOT the
         cumulative diff — that's Phase 2). Max 3 fix iterations per
         story. If review fails after 3 iterations: hard story failure
         (Phase 1.5 below).

    1.6  Security (gstack/cso) — conditional
         If story.affected_modules touches any HIPAA path (Profile,
         Client, Evaluation, Survey, Auth, Storage):
           head -100 ~/.claude/skills/gstack/cso/SKILL.md
           Run OWASP Top 10 + STRIDE audit on the per-story diff.
           Apply the confidence gate (8/10+) and false-positive
           exclusions per the gstack skill.
           If a critical vuln is found: fix, re-audit. If unfixable
           after 2 iterations: hard story failure.
         Otherwise: skip with a note in PIPELINE.md.

    1.7  QA (gstack/qa)
         head -100 ~/.claude/skills/gstack/qa/SKILL.md
         Run automated tests for each touched repo. Visual/browser tests
         only if the story explicitly requires UI verification (UX-DR
         acceptance criteria). If a bug is found: fix, generate
         regression test, re-verify.

    1.8  Atomic commit (per repo)
         For each repo in REPOS:
           cd workspace/<repo>
           git add -A
           git commit -m "[Story <N.M>] <story title>"
         Do NOT push yet — push happens once at end of run.

    1.9  Bookkeeping
         If this story maps to a GitHub user-story issue:
           gh issue edit <num> --add-label oracle:story-done
         Update PIPELINE.md story section `## Status: COMPLETE`.

    On hard failure at any step (1.1–1.7): go to Phase 1.5 below.
```

**Per-story Iron Law:** every commit's diff must be a strict subset of
SCOPE. Out-of-scope edits accumulate into the project-level
`scope_deviations` list — they do NOT cause the story to fail, but they DO
cause the resulting PRs to carry the `scope-deviation` label and skip
auto-deploy.

**Why per-story (not per-project) gstack phases:** stories are the BMAD unit
of correctness. Investigating cumulatively means a late story can pollute
the investigation of an earlier story. Reviewing cumulatively means a
20-file diff in front of the reviewer prompt drowns out the per-story
intent. Per-story gstack keeps each unit's investigation, review, and
security audit focused on its own diff and its own acceptance criteria.

**Context budget per story:** if you find yourself reading the same gstack
SKILL.md head-100 multiple times in one project run, stop. Read each one
ONCE per project run, keep it in context for all stories.

### Phase 1.5 — Failure Handling

```bash
gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Pipeline failed at story $FAILED_STORY: $ERROR_SUMMARY"

# Roll labels back across the whole group so a re-trigger is possible
jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
  gh issue edit "$n" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label oracle:implementing \
    --add-label oracle:blocked-pipeline-failed
done
```

Leave the project branches at the last successful story's commit. Do NOT
push, do NOT open PRs, do NOT trigger deploy. A re-application of
`maestro-ready` to any story in the group will resume from `$FAILED_STORY`
(orchestrator detects last commit, reads next story, runs from there).
Update PIPELINE.md `## Status` to `FAILED_AT_STORY_<N.M>`. Exit non-zero.

---

## Phase 2 — Cumulative Scope Audit

```bash
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  CHANGED=$(git diff --name-only origin/main..HEAD)
  ALLOWED=$(union of every story's affected_modules + new_files_needed for this repo)
  DEVIATIONS=$(comm -23 <(echo "$CHANGED" | sort) <(echo "$ALLOWED" | sort))
  cd /tmp/oracle-work
done
```

If `scope_deviations` is non-empty across any repo, that repo's PR gets the
`scope-deviation` label and the deploy step is **skipped**.

---

## Phase 3 — Multi-Repo PR Group

Push and open one PR per repo, all targeting `main`. PRs are linked by
`group:project-<slug>` so reviewers can navigate the group.

```bash
PR_TITLE="[Oracle Project: $PROJECT_SLUG] $PROJECT_NAME"

for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  git push --force-with-lease -u origin "$BRANCH"

  PR_BODY=$(build_pr_body)  # links to anchor issue, list of group user-stories,
                            # stories implemented from BMAD ordering, scope notes,
                            # "Do not merge until all PRs in group are approved"

  LABELS="oracle-project,group:project-$PROJECT_SLUG,$PROJECT_LABEL"
  [ -n "$REPO_DEVIATIONS" ] && LABELS="$LABELS,scope-deviation"

  EXISTING=$(gh pr list --repo "$TARGET_ORG/$REPO" \
    --head "$BRANCH" --state open --json number,url | jq '.[0]')
  if [ "$EXISTING" != "null" ]; then
    gh pr edit "$(echo "$EXISTING" | jq -r .number)" \
      --repo "$TARGET_ORG/$REPO" \
      --title "$PR_TITLE" --body "$PR_BODY" --add-label "$LABELS"
    PR_URL=$(echo "$EXISTING" | jq -r .url)
  else
    PR_URL=$(gh pr create --repo "$TARGET_ORG/$REPO" \
      --base main --head "$BRANCH" \
      --title "$PR_TITLE" --body "$PR_BODY" --label "$LABELS")
  fi

  PR_URLS["$REPO"]="$PR_URL"
  PR_SHAS["$REPO"]="$(git rev-parse HEAD)"
  cd /tmp/oracle-work
done

gh issue comment "$ANCHOR_ISSUE" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Pipeline complete — PRs: $(format_pr_list)"
```

> **Multi-repo PR orchestration tools.** This loop is hand-rolled because
> Oracle stories produce *different* diffs per repo (per-story, per-repo
> implementation). For the lifecycle phase (group merge / close / status),
> see the sibling skill `oracle-pipeline-lifecycle/` which wraps
> **multi-gitter** for those same-action-many-repos operations. Full
> evaluation in `docs/multi-repo-tools.md`.

---

## Phase 4 — Trigger Ephemeral Deploy

If — and only if — `scope_deviations` is empty across all repos:

```bash
gh api "repos/$TARGET_ORG/infra/dispatches" \
  --method POST \
  --field event_type='oracle.project.complete' \
  --field "client_payload[project_slug]=$PROJECT_SLUG" \
  --field "client_payload[anchor_issue_number]=$ANCHOR_ISSUE" \
  --field "client_payload[involved_repos]=$(jq -nc --argjson r "$INVOLVED_REPOS_JSON" '$r')" \
  --field "client_payload[git_sha_per_repo]=$(jq -nc --argjson s "$PR_SHAS_JSON" '$s')" \
  --field "client_payload[bmad_context_path]=bmad-context/$PROJECT_SLUG"

# Move every user-story in the group from implementing → deploying
jq -r '.[].number' /tmp/oracle-work/stories.json | while read n; do
  gh issue edit "$n" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label oracle:implementing \
    --add-label oracle:deploying
done
```

If scope deviations exist: post a comment on the anchor issue listing them,
leave the `scope-deviation` label on each PR, and DO NOT dispatch deploy.

---

## Phase 5 — Emit Structured Output

Print the final structured output to stdout:

```json
{
  "project_slug": "asset-management-system-ams",
  "project_label": "project: Asset Management System (AMS)",
  "anchor_issue_number": 286,
  "group_user_stories": [273, 274, 275, ...],
  "stories_implemented": ["1.1", "1.2", "1.3", "2.1"],
  "prs": [
    {"repo": "carespace-admin", "url": "...", "sha": "abc123", "files_modified": [...]},
    {"repo": "carespace-ui",    "url": "...", "sha": "def456", "files_modified": [...]}
  ],
  "scope_deviations": [],
  "duration_seconds": 8421,
  "tokens_used": null,
  "failed_at_story": null
}
```

Update PIPELINE.md `## Status` to `COMPLETE` (or
`COMPLETE_WITH_SCOPE_DEVIATIONS`).

---

## Audit Logging

Emit one structured stdout line per state transition:

```json
{"project_slug":"...","anchor_issue_number":286,"story_id":"1.2",
 "action":"story_committed","actor":"maestro-orchestrator",
 "timestamp":"2026-04-30T10:23:00Z","outcome":"success","cost_estimate":null}
```

Required actions: `project_picked_up`, `repos_cloned`, `branch_created`,
`story_committed`, `scope_audit_complete`, `pr_opened`, `deploy_dispatched`,
`pipeline_failed`, `pipeline_complete`.

---

## Iteration Guard

If a single story burns 3 inline fix attempts and still fails, treat it as a
hard story failure (Phase 1.5).

If the project as a whole has more than 5 hard story failures across the
session, abort with `PIPELINE_RUNAWAY` and require human review.

---

## Final Output

```
COMPLETE: project=<slug> anchor=#<N> group=[<list>]
PRs:
  <repo-1>: <url-1>
  <repo-2>: <url-2>
Stories: <N>/<N>
Scope deviations: <count>
Deploy dispatched: <yes|no>
```
