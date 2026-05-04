---
name: oracle-pipeline
description: Autonomous BMAD developer for the Oracle backlog. Implements every story in a project end-to-end (create-story → dev-story → tests → coverage → lint → code-review → commit), iterating until acceptance criteria pass. One anchor issue per project, one cumulative PR per affected repo. Trigger keywords oracle pipeline, maestro-ready, project_slug, bmad implementation, oracle backlog
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TodoWrite, Task
---

# Oracle Pipeline (BMAD Developer)

**Role:** Autonomous BMAD developer for the multi-repo Oracle backlog.
**Core purpose:** Take a planned BMAD project (epics + stories already authored)
and implement it to a "ready-to-merge" state — code, tests, coverage ≥ 80%,
lint clean, code-reviewed — then open one cumulative PR per affected repo.

This skill is the BMAD `developer` role with multi-repo orchestration on top.
The story lifecycle is the developer skill; the wrapper handles anchor issues,
repo cloning, BMAD installation, code-graph indexing, and PR groups.

## When to Use

Trigger this skill when:
- An anchor issue carries `bmad` + `maestro-ready` (fresh start)
- A `maestro:implementing` issue exists with a stale feature branch (resume)
- `CLAUDEHUB_INPUT_KWARGS` contains `project_slug` (targeted run)

Do NOT use this skill for:
- Authoring epics or stories (that's the planning side, separate skills)
- Single-file fixes (use a regular dev workflow)
- Anything outside the Oracle backlog protocol

## Required Environment

| Var | Purpose |
|-----|---------|
| `GITHUB_TOKEN` | gh CLI auth, push, PR create |
| `TARGET_ORG` | GitHub org (default `carespace-ai`) |
| `CLAUDEHUB_INPUT_KWARGS` | optional JSON with `project_slug` |
| `NOTIFICATION_WEBHOOK_URL` | optional pipeline-complete ping |
| `COVERAGE_THRESHOLD` | optional, default 80 |

Tools required on PATH: `gh`, `jq`, `git`, `python3`, `npx`, `claude`,
`serena`, `code-graph-mcp`.

## Pipeline Flow

```
phase 00  → discover anchor issue, derive project slug, mark implementing
phase 01  → clone backlog, fetch BMAD context, parse stories
phase 02  → clone target repos, install BMAD, index code-graph, write PIPELINE.md
phase 03  → for each story: create → dev → gates → review → commit  (LOOP)
phase 04  → push branches, open PR group, dispatch deploy
phase 05  → finalize PIPELINE.md, optional webhook, emit JSON
```

## Story Lifecycle (BMAD Developer Loop)

For each story in `stories-order.txt` that is not already committed:

1. **bmad-create-story** — generate the story file
2. **bmad-dev-story** — implement (Serena + code-graph for navigation)
   - On `halted` → retry once with halt reason; second halt → fail story
3. **Quality gates** — `lint-check.sh` + `check-coverage.sh`
   - On gate fail → re-run dev-story with gate failure as context; second fail → fail story
4. **bmad-code-review** — self-review against [code-review.template.md](templates/code-review.template.md)
   - On `changes_requested` → re-run dev-story with findings
5. **pre-commit-check.sh** — final lint + coverage before staging
6. **Atomic commit per repo** — `[Story <KEY>] <title>`

After last story per epic → comment `Epic N complete`.

## Iteration Guards

- **Per story:** dev-story may halt at most twice → fail story, increment `HARD_FAILURES`
- **Per story:** quality gates may fail at most twice → fail story
- **Whole project:** `HARD_FAILURES ≥ 5` → label `maestro:blocked`, abort with `PIPELINE_RUNAWAY`

## Running the Pipeline

End-to-end (called by ClaudeHub or run locally with the env set):

```bash
SKILL=$HOME/.claude/skills/oracle-pipeline   # or the maestro-skills path

bash $SKILL/scripts/00-discover-anchor.sh
bash $SKILL/scripts/01-setup-workspace.sh
bash $SKILL/scripts/02-prepare-repos.sh

. /tmp/oracle-work/env.00.sh
. /tmp/oracle-work/env.01.sh
. /tmp/oracle-work/env.02.sh

HARD_FAILURES=0; LAST_EPIC=0; EPIC_COUNT=0
while IFS=$'\t' read -r EPIC STORY TITLE; do
  [ -z "$STORY" ] && continue
  if [ "$EPIC" != "$LAST_EPIC" ] && [ "$LAST_EPIC" -gt 0 ]; then
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "Epic $LAST_EPIC complete — $EPIC_COUNT stories implemented."
    EPIC_COUNT=0
  fi
  LAST_EPIC="$EPIC"

  set +e
  bash "$SKILL/scripts/03-run-story.sh" "$EPIC" "$STORY" "$TITLE"
  rc=$?
  set -e

  case $rc in
    0) EPIC_COUNT=$((EPIC_COUNT+1)) ;;
    1) HARD_FAILURES=$((HARD_FAILURES+1))
       [ $HARD_FAILURES -ge 5 ] && {
         gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
           --body "PIPELINE_RUNAWAY: 5 hard failures — aborting"
         gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
           --remove-label maestro:implementing --add-label maestro:blocked
         exit 2; } ;;
    2) : ;;  # skipped (already committed)
  esac
done < /tmp/oracle-work/stories-order.txt

[ "$LAST_EPIC" -gt 0 ] && \
  gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
    --body "Epic $LAST_EPIC complete — $EPIC_COUNT stories implemented."

export HARD_FAILURES
bash $SKILL/scripts/04-open-prs.sh
bash $SKILL/scripts/05-finalize.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| [scripts/00-discover-anchor.sh](scripts/00-discover-anchor.sh) | gh auth, anchor discovery, resume detection |
| [scripts/01-setup-workspace.sh](scripts/01-setup-workspace.sh) | clone backlog, fetch context, parse stories |
| [scripts/02-prepare-repos.sh](scripts/02-prepare-repos.sh) | clone repos, install BMAD, code-graph index |
| [scripts/03-run-story.sh](scripts/03-run-story.sh) | one full story lifecycle with gates |
| [scripts/04-open-prs.sh](scripts/04-open-prs.sh) | push + PR group + deploy dispatch |
| [scripts/05-finalize.sh](scripts/05-finalize.sh) | PIPELINE.md, output JSON, webhook |
| [scripts/lint-check.sh](scripts/lint-check.sh) | auto-detect linter (npm/eslint/ruff/flake8/go vet) |
| [scripts/check-coverage.sh](scripts/check-coverage.sh) | auto-detect runner; enforce ≥ 80% |
| [scripts/pre-commit-check.sh](scripts/pre-commit-check.sh) | final lint + coverage gate |

## Templates and Resources

- [templates/pipeline-md.template](templates/pipeline-md.template) — PIPELINE.md skeleton
- [templates/mcp-config.json.template](templates/mcp-config.json.template) — per-repo Serena + code-graph
- [templates/code-review.template.md](templates/code-review.template.md) — self-review checklist
- [resources/extract-stories.py](resources/extract-stories.py) — BMAD stories-output.md parser
- [resources/clean-code-checklist.md](resources/clean-code-checklist.md) — code quality bar
- [resources/testing-standards.md](resources/testing-standards.md) — coverage + test type guidance
- [resources/carespace-context.md](resources/carespace-context.md) — org-specific context (load only if needed)

## Subagent Strategy

This skill leverages parallel subagents for independent work units. Each
subagent has a fresh context window — pass it only the files it needs.

### Pattern 1: Parallel Story Implementation
**When:** Sprint contains 2+ stories with no shared file scope (different
`affected_modules`).
**Pattern:** Story Parallel Implementation with worktree isolation.

| Agent | Task | Output |
|-------|------|--------|
| Agent N | Run `03-run-story.sh` for one story in an isolated worktree | Committed branch |

```
Use Task tool with:
- subagent_type: "general-purpose"
- isolation: "worktree"
- run_in_background: true
- prompt: "Run scripts/03-run-story.sh <epic> <story> <title>. The story
  scope is <affected_modules>. Do not touch files outside that list.
  Return JSON: {story_key, status, commit_sha}."
```

Coordination: launch all parallel agents, await all, then run a single
integration test pass in main context before opening PRs.

### Pattern 2: Fan-Out Code Review
**When:** Multiple repos changed, each PR can be reviewed in parallel.

| Agent | Task | Output |
|-------|------|--------|
| Agent per repo | Review the diff using code-review.template.md | review-{repo}.md |

### Pattern 3: Per-Repo Lint + Coverage Fan-Out
**When:** Quality gates on N repos.

| Agent per repo | Run lint-check.sh + check-coverage.sh; report findings | gate-{repo}.json |

### When NOT to parallelize
- Single-story projects
- Stories with overlapping `affected_modules` (file conflicts)
- Tight resume scenarios (sequentially safer)

## Token Optimization

This skill is intentionally lean:
- **Scripts hold the bash, not the markdown.** Claude calls
  `bash scripts/NN-*.sh` instead of reading markdown to copy bash blocks.
- **REFERENCE.md is lazy-loaded.** Only read when debugging or extending the
  pipeline; nothing in the normal flow reads it.
- **carespace-context.md is opt-in.** Loaded only if a story needs org-specific
  background; otherwise ignored.
- **Repo navigation uses Serena + code-graph**, never bulk Read.
- One `claude --print` subprocess per BMAD step — output captured to a variable.

## Error Handling

| Failure | Action |
|---------|--------|
| `GITHUB_TOKEN` invalid | exit 1 immediately |
| Anchor not found | exit 0 (nothing to do) or exit 1 (slug given but missing) |
| BMAD context missing | comment + label `maestro:blocked-pipeline-failed`, exit 1 |
| Concurrency cap (>2 active) | exit 0, leave label alone |
| BMAD workflow files missing | exit 1 |
| Serena / code-graph missing | exit 1 (rebuild Docker image) |
| dev-story halts twice | fail story, increment counter |
| Gates fail twice | fail story, increment counter |
| `HARD_FAILURES ≥ 5` | label `maestro:blocked`, exit 2 |

## Notes for Execution

- **Never re-read a file already in context.** Phase env files
  (`env.0N.sh`) are sourced, not Read'd.
- **Story scope is enforced.** dev-story is told to touch only files matching
  `affected_modules`; pre-commit-check is the final guard.
- **Code-graph is mandatory** for large repos — Serena `find_symbol` /
  `get_file_outline` replace bulk Read.
- **Commits are atomic per story per repo.** A failed story leaves the prior
  commit intact, so resume always works.
- **Anchor issue is the only progress surface.** Per-story comments are limited
  to halts and epic gates to keep the timeline readable.

## See Also

- [REFERENCE.md](REFERENCE.md) — full pipeline state machine, recovery flows,
  failure-mode table, and rationale.
