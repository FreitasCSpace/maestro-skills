---
name: oracle-pipeline
description: |
  Autonomous project-level dev pipeline — implements an entire Oracle backlog
  project (all epics + all user stories) in one session.
  Triggered by a `project-meta` issue in `the-oracle-backlog` carrying the
  `maestro-ready` label. Consumes the project's BMAD context, iterates every
  story in dependency order, opens one cumulative PR per affected repo, and
  fires a `repository_dispatch` event to deploy the ephemeral review env.
---

# Oracle Pipeline (project-level)

You are an autonomous **project-level** development pipeline. The unit of work
is an entire Oracle backlog project: every epic and every user story in the
project's `stories-output.md`, executed in BMAD-defined dependency order, in a
single session. There is NO per-story human gate.

This skill is a project-level adaptation of the original `pipeline` skill.
Differences vs `pipeline/` at a glance:

| `pipeline/`                     | `oracle-pipeline/` (this skill)            |
|---------------------------------|--------------------------------------------|
| Trigger: single GitHub issue    | Trigger: `project-meta` issue + `maestro-ready` label |
| Clones one repo                 | Clones every repo in `feature_intent.involved_repos` |
| One commit, one PR              | Atomic commit per story, one cumulative PR per affected repo |
| Branch: `pipeline/issue-N-...`  | Branch: `feat/oracle-project-<slug>` per repo |
| Targets `develop`               | Targets `main`, labeled `oracle-project`, `group:project-<slug>`, original `project:` label |
| No scope guardrail              | Cumulative scope guardrail vs union of `affected_modules + new_files_needed` |
| No structured output            | Emits `oracle.project.complete` JSON event via `repository_dispatch` to `carespace-ai/infra` |

**CRITICAL FIRST STEP — DO THIS BEFORE ANYTHING ELSE:**

Any files in the current working directory are STALE from a previous pipeline
run. Do NOT read them. Do NOT look at PIPELINE.md. Do NOT assume any work is
done. This is a BRAND NEW project run. Ignore everything in the current
directory.

Your very first action must be to read the task input, identify the
`project-meta` issue, and clone fresh repos under `/tmp/oracle-work/`.
NEVER say "already completed" — every run is a new project.

---

## Tool Loading Strategy (saves context)

This session runs with `ENABLE_TOOL_SEARCH=true`. Tools and skills are NOT
pre-loaded into context. Use `ToolSearch` to load tools when you need them.

**Only load tools/skills for the phase you're currently executing.**

- Setup phase: you already have Bash, Read, Write — no ToolSearch needed
- Per-story build: `ToolSearch` with `"select:Edit,Grep,Glob"` when you first need them
- QA phase: `ToolSearch` for `"browser playwright"` only if visual testing is needed

---

## CareSpace Codebase Context (READ THIS FIRST)

Before doing ANYTHING — even before parsing the task — read the CareSpace
codebase context. **This file is your map.**

```bash
cat ~/.claude/skills/oracle-pipeline/CARESPACE_CONTEXT.md
```

You read this file ONCE per session. Never read it again.

After reading, use it to:

1. **Identify each target repo before cloning** — `feature-intent.json`'s
   `involved_repos[].full_name` lists every repo the project touches. Match
   each to the Repository Map.
2. **Use the per-repo "Where to look by issue type" tables** to jump directly
   to the relevant folder for each story's affected modules.
3. **Check the HIPAA notes** before touching any file that handles PHI
   (Profile, Client, Evaluation, Survey, etc).

---

## Anti-Waste Rules (MANDATORY)

### 1. Never re-read a file you already read
Once read, the file is in your context. Don't re-read unless modified or the
user asks. Applies to:
- `CARESPACE_CONTEXT.md` (read ONCE at start)
- The project-meta issue body (`gh issue view` ONCE)
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

---

## Step 0 — Setup

### 0.1 Read task input

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Extract these required fields from the input:

- `meta_issue_number` — the `project-meta` issue number in `the-oracle-backlog`
- `project_slug` — slugified `project:` label value (lowercase, hyphenated)
- `bmad_context_dir` — path under `the-oracle-backlog/bmad-context/<slug>/`
- `target_org` — defaults to `carespace-ai`
- `github_app_token` — short-lived installation token (provided via env)

If any field is missing, fail fast: comment on the meta-issue (if known) with
`Pipeline input incomplete: missing <fields>` and remove the `maestro-ready`
label.

### 0.2 Authenticate GitHub

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status
```

The token is the AI's GitHub App installation token. It can:
- Read all in-scope `carespace-ai` repos
- Push **only** to `refs/heads/feat/oracle-project-*` on those repos

It cannot push to `main`. If a push to `main` succeeds, that is a P0 ruleset
breach — abort the run and page on-call.

### 0.3 Wipe and prepare workspace

```bash
rm -rf /tmp/oracle-work 2>/dev/null
mkdir -p /tmp/oracle-work
cd /tmp/oracle-work
```

**You MUST work in `/tmp/oracle-work` for the entire run.**

### 0.4 Fetch the project-meta issue

```bash
gh issue view "$META_ISSUE_NUMBER" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --json number,title,body,labels,state
```

Verify:
- The issue carries the `project-meta` AND `maestro-ready` labels
- The issue is `OPEN`
- Exactly one `project:<slug>` label is present and matches `$PROJECT_SLUG`

If any check fails, comment with the reason, remove `maestro-ready`, and exit.

### 0.5 Load and validate BMAD context (FR3)

Clone the backlog repo (read-only) and validate the context dir:

```bash
gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- --depth=1
cd backlog/bmad-context/$PROJECT_SLUG

REQUIRED=(feature-intent.json architecture.md prd.md front-end-spec.md stories-output.md)
MISSING=()
for f in "${REQUIRED[@]}"; do
  [ -f "$f" ] || MISSING+=("$f")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  gh issue comment "$META_ISSUE_NUMBER" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "BMAD context incomplete: missing ${MISSING[*]}"
  gh issue edit "$META_ISSUE_NUMBER" \
    --repo "$TARGET_ORG/the-oracle-backlog" \
    --remove-label maestro-ready
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

### 0.6 Clone every involved repo (FR5)

For each `repo` in `involved_repos`:

```bash
mkdir -p /tmp/oracle-work/workspace
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

### 0.7 Create or reset the project branch (FR6, FR25)

For each cloned repo, create `feat/oracle-project-<slug>` off latest `main`.
Idempotency rules:

```bash
BRANCH="feat/oracle-project-$PROJECT_SLUG"
for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  git fetch origin main "$BRANCH" 2>/dev/null || git fetch origin main

  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    # Branch exists — verify all commits authored by AI App identity
    NON_AI=$(git log "origin/main..origin/$BRANCH" \
      --pretty='%ae' | grep -v '^oracle-pipeline@carespace\.ai$' | head -1)
    if [ -n "$NON_AI" ]; then
      gh issue comment "$META_ISSUE_NUMBER" \
        --repo "$TARGET_ORG/the-oracle-backlog" \
        --body "Human commits detected on AI project branch in $REPO — manual reconciliation required"
      exit 1
    fi
    # Reset to main, force-push later
    git checkout -B "$BRANCH" origin/main
  else
    git checkout -B "$BRANCH" origin/main
  fi

  cd /tmp/oracle-work
done
```

### 0.8 Auto-detect stack and install per repo

Same logic as the original `pipeline` skill, but run for each cloned repo.
Detection in priority order: `package-lock.json` → `yarn.lock` → `bun.lock` →
`package.json` → `build.gradle*` → `go.mod` → `requirements.txt` →
`pyproject.toml` → `pubspec.yaml` → `Gemfile`.

Generate a temporary `CLAUDE.md` per repo if missing (same template as
`pipeline/`). Do NOT commit a generated `CLAUDE.md` on the project branch.

### 0.9 Write the master PIPELINE.md

At `/tmp/oracle-work/PIPELINE.md`:

```markdown
# Oracle Project Pipeline Run

## Project
slug: <project-slug>
meta-issue: <org>/the-oracle-backlog#<N>
involved repos: <list>
total stories: <N>

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

### 0.10 Acquire concurrency slot (FR19)

```bash
ACTIVE=$(gh issue list --repo "$TARGET_ORG/the-oracle-backlog" \
  --label oracle:implementing --state open --json number | jq length)

if [ "$ACTIVE" -ge 2 ]; then
  echo "Concurrency cap reached ($ACTIVE active envs); leaving maestro-ready in place"
  exit 0
fi

gh issue edit "$META_ISSUE_NUMBER" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --add-label oracle:implementing \
  --remove-label maestro-ready
```

---

## Phase 1 — Story Iteration (the meat)

For each story in BMAD dependency order, run a compact build cycle.

```
for story in stories_output.md (in order):
    1. Identify which involved_repos this story touches
    2. For each touched repo:
        a. cd workspace/<repo>
        b. Compose AI prompt: story acceptance criteria, dev notes,
           feature-intent.json scoped to this repo, relevant
           architecture.md sections, current contents of every path in
           story.affected_modules, list of new_files_needed
        c. Apply the implementation (Edit / Write tools)
        d. Run the project's test command (from CLAUDE.md or auto-detected)
        e. If tests fail and the failure is fixable inline: fix and re-run
           (max 2 inline fix attempts per story per repo)
        f. Capture diff vs HEAD: every modified path MUST be in
           (story.affected_modules ∪ story.new_files_needed). Record any
           paths outside this set in scope_deviations[].
        g. git add -A
        h. git commit -m "[Story <N.M>] <story title>"
        i. Do NOT push yet — push happens once at end of run
    3. Append `### Story <N.M>` to PIPELINE.md with: repos touched, files
       modified, test outcome, scope_deviations
    4. If any repo's tests still fail after inline retries, OR if a hard
       error occurred: STOP. Go to Phase 1.5 (failure handling).
```

**Per-story Iron Law:** every commit's diff must be a strict subset of the
union of that story's `affected_modules` and `new_files_needed`.
Out-of-scope edits accumulate into the project-level `scope_deviations` list
(FR8) — they do NOT cause the story to fail, but they DO cause the resulting
PRs to carry the `scope-deviation` label and skip auto-deploy.

### Phase 1.5 — Failure Handling (FR26)

```bash
gh issue comment "$META_ISSUE_NUMBER" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Pipeline failed at story $FAILED_STORY: $ERROR_SUMMARY"

gh issue edit "$META_ISSUE_NUMBER" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --remove-label oracle:implementing \
  --add-label oracle:blocked-pipeline-failed
```

Leave the project branches at the last successful story's commit. Do NOT
push, do NOT open PRs, do NOT trigger deploy. A re-label of `maestro-ready`
will resume from `$FAILED_STORY`. Update PIPELINE.md `## Status` to
`FAILED_AT_STORY_<N.M>`. Exit non-zero.

---

## Phase 2 — Cumulative Scope Audit (FR8)

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
`scope-deviation` label and the deploy step is **skipped** (FR8).

---

## Phase 3 — Multi-Repo PR Group (FR9)

Push and open one PR per repo, all targeting `main`. PRs are linked by
`group:project-<slug>` so reviewers can navigate the group.

```bash
PR_TITLE="[Oracle Project: $PROJECT_SLUG] $PROJECT_NAME"

for REPO in "${INVOLVED_REPOS[@]}"; do
  cd "workspace/$REPO"
  git push --force-with-lease -u origin "$BRANCH"

  PR_BODY=$(build_pr_body)  # links to meta-issue, stories list, scope notes,
                            # "Do not merge until all PRs in group are approved"

  LABELS="oracle-project,group:project-$PROJECT_SLUG,project:$PROJECT_SLUG"
  [ -n "$REPO_DEVIATIONS" ] && LABELS="$LABELS,scope-deviation"

  # Idempotent: update existing PR or create new
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

gh issue comment "$META_ISSUE_NUMBER" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --body "Pipeline complete — PRs: $(format_pr_list)"
```

> **Implementation tip — multi-repo PR orchestration tools.** The loop above
> is a hand-rolled multi-repo PR opener. There are two existing OSS tools
> that do exactly this kind of "apply changes to N repos, open PRs in batch"
> pattern, and we should evaluate (not necessarily adopt) them:
>
> - **multi-gitter** (Go, lindell/multi-gitter) — runs an arbitrary script
>   inside each repo, then opens a PR per repo via the GitHub/GitLab/Bitbucket
>   API. Has built-in `merge` / `status` / `close` subcommands that map
>   directly to FR17 (approval merge) and FR18 (rejection cleanup). License:
>   MIT.
> - **turbolift** (Go, skyscanner/turbolift) — repo-list driven. Forks +
>   branches + PRs per repo. Better suited when each repo gets the *same*
>   conceptual change. Less flexible than multi-gitter for our use case
>   because Oracle stories produce *different* diffs per repo.
>
> See `docs/multi-repo-tools.md` for the full evaluation and
> `skills/oracle-pipeline-lifecycle/` for the wired-up sibling skill that
> wraps multi-gitter for FR15 (group status), FR17 (group merge), and FR18
> (group close + prune). The hand-rolled loop above is correct here because
> we already have per-repo diffs committed locally — we don't need a tool
> to "apply the same change everywhere," we just need to push + PR each
> repo. multi-gitter's value is in the lifecycle, not the implementation.

---

## Phase 4 — Trigger Ephemeral Deploy (FR10)

If — and only if — `scope_deviations` is empty across all repos:

```bash
gh api "repos/$TARGET_ORG/infra/dispatches" \
  --method POST \
  --field event_type='oracle.project.complete' \
  --field "client_payload[project_slug]=$PROJECT_SLUG" \
  --field "client_payload[meta_issue_number]=$META_ISSUE_NUMBER" \
  --field "client_payload[involved_repos]=$(jq -nc --argjson r "$INVOLVED_REPOS_JSON" '$r')" \
  --field "client_payload[git_sha_per_repo]=$(jq -nc --argjson s "$PR_SHAS_JSON" '$s')" \
  --field "client_payload[bmad_context_path]=bmad-context/$PROJECT_SLUG"

gh issue edit "$META_ISSUE_NUMBER" \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --remove-label oracle:implementing \
  --add-label oracle:deploying
```

If scope deviations exist: post a comment listing them, leave the
`scope-deviation` label on each PR, and DO NOT dispatch the deploy event.

---

## Phase 5 — Emit Structured Output

Print the final structured output (matches `architecture.md §5.2`):

```json
{
  "meta_issue_number": 500,
  "project_slug": "asset-management-system-ams",
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

## Audit Logging (FR24)

Emit one structured stdout line per state transition (Maestro forwards
stdout to Log Analytics):

```json
{"project_slug":"...","meta_issue_number":500,"story_id":"1.2",
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
COMPLETE: project=<slug> meta-issue=#<N>
PRs:
  <repo-1>: <url-1>
  <repo-2>: <url-2>
Stories: <N>/<N>
Scope deviations: <count>
Deploy dispatched: <yes|no>
```
