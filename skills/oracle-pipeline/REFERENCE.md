# Oracle Pipeline — Detailed Reference

This document holds the deep mechanics of the pipeline. Don't load it during a
normal run — it's for debugging, extending, and audit.

## State Files

All state lives under `/tmp/oracle-work/`:

```
/tmp/oracle-work/
├── env.00.sh              # ANCHOR, PROJECT_*, RESUME_MODE
├── env.01.sh              # PLANNING_DIR, INVOLVED_REPOS, TOTAL_STORIES
├── env.02.sh              # BRANCH, WF_*, COMPLETED_STORIES
├── env.04.sh              # PR_URLS (associative array)
├── stories-order.txt      # tab-separated EPIC<tab>STORY<tab>TITLE
├── story-meta/N-M.sh      # STORY_AFFECTED_MODULES + STORY_AC per story
├── stories/<KEY>.md       # bmad-create-story output
├── PIPELINE.md            # human-readable run log
├── backlog/               # cloned the-oracle-backlog (depth=1)
├── bmad-workflows/        # sparse-cloned BMAD workflow repo
└── workspace/<repo>/      # one cloned target repo per involved repo
    └── .mcp.json          # per-repo Serena + code-graph config
```

## Anchor Issue State Machine

```
              maestro-ready
                   │
                   ▼  (phase 00)
            maestro:implementing
                   │
        ┌──────────┼──────────┐
        ▼          │          ▼
   PRs opened  branch stale  ≥5 failures
        │      (resume next  │
        ▼       run)         ▼
   maestro:deploying    maestro:blocked
```

Labels emitted by the pipeline:
- `maestro:implementing` — phase 00 marks, phase 04 removes
- `maestro:deploying` — phase 04 sets after PRs open
- `maestro:blocked` — runaway (HARD_FAILURES ≥ 5)
- `maestro:blocked-pipeline-failed` — BMAD context missing
- `oracle-project`, `group:project-<slug>` — applied to PRs

## Anchor Discovery (phase 00)

Three modes, tried in order:

### Mode A: explicit slug
`CLAUDEHUB_INPUT_KWARGS.project_slug` is set. Find the open `bmad`-labeled
issue whose `project: <name>` label normalizes to that slug. If none, exit 1.

### Mode B1: resume orphan
Walk all open `maestro:implementing` issues. For each, derive the slug from
its `project: <name>` label, then check the feature branch
`feat/oracle-project-<slug>` in each involved repo. If the most recent commit
is older than 90 minutes (5400s) on every repo, treat it as orphaned and
resume from there.

### Mode B2: fresh start
Pick the first open issue with both `bmad` and `maestro-ready`. If none, and
no orphan was resumable in B1, exit 0 (nothing to do).

## Resume Logic (phase 02 → phase 03)

`COMPLETED_STORIES` is computed in phase 02 from commit subjects on the
feature branch:

```bash
git log "origin/${DEFAULT_BRANCH}..$BRANCH" --format="%s" \
  | grep -oE '\[Story [A-Za-z0-9._-]+\]' \
  | sed 's/\[Story //;s/\]//'
```

In phase 03, each story key is checked against this array; matches are
skipped. The first un-skipped story posts a "resuming from Epic N, Story
N.M" comment to the anchor issue.

## Story Lifecycle (phase 03) — Failure Tree

```
bmad-create-story
        │
        ▼
bmad-dev-story (1st attempt)
   ├─ status: review     → continue
   └─ status: halted     → comment, retry
                          ├─ review     → continue
                          └─ halted     → fail story (+1 HARD_FAILURES)

Quality gates: lint + coverage
   ├─ pass               → continue
   └─ fail               → re-run dev-story with gate context
                          ├─ pass on 2nd → continue
                          └─ fail again  → fail story (+1 HARD_FAILURES)

bmad-code-review
   ├─ approved              → continue
   └─ changes_requested     → re-run dev-story with findings, then continue

pre-commit-check (lint + coverage final)
   ├─ pass    → atomic commit per repo
   └─ fail    → fail story (+1 HARD_FAILURES)
```

`HARD_FAILURES ≥ 5` → label `maestro:blocked` and abort.

## Per-Repo Quality Gate Auto-Detection

[`scripts/lint-check.sh`](scripts/lint-check.sh) probes in this order:

1. `package.json` with `scripts.lint` → `npm run lint`
2. `package.json` with eslint binary → `eslint . --max-warnings=0`
3. `pyproject.toml` / `ruff.toml` + `ruff` → `ruff check .`
4. `setup.cfg` / `.flake8` + `flake8` → `flake8 .`
5. `go.mod` → `go vet ./...`
6. None → no-op (exit 0)

[`scripts/check-coverage.sh`](scripts/check-coverage.sh):

1. `package.json` `scripts.test` → `npm run test:coverage` if defined,
   else `npm test -- --coverage`. Reads `coverage/coverage-summary.json`,
   compares `total.lines.pct` to `COVERAGE_THRESHOLD` (default 80).
2. Python project + `pytest` → `pytest --cov=. --cov-fail-under=$THRESHOLD`
3. Go module → `go test -cover ./...`, parse `coverage: N%`
4. None → no-op (exit 0)

Override the threshold per-run with `COVERAGE_THRESHOLD=90`.

## BMAD Workflow Source

Workflows are sparse-cloned from `FreitasCSpace/carespace-bmad-workflow`:

```
bmad-template/bmm/workflows/4-implementation/
├── bmad-create-story/workflow.md
├── bmad-dev-story/workflow.md
└── bmad-code-review/workflow.md
```

These are not copied into target repos — they're invoked as `cat <workflow.md>`
inserted into a `claude --print` prompt at runtime.

## Code-Graph + Serena

Each cloned repo gets a `.mcp.json` (rendered from
[`templates/mcp-config.json.template`](templates/mcp-config.json.template))
that exposes two MCP servers to `claude --print` subprocesses:

- **serena** — LSP-backed `find_symbol`, `get_file_outline`, `find_references`
- **code-graph** — semantic search across the repo

`code-graph-mcp incremental-index` runs once per repo in phase 02 with a
5-minute timeout. If indexing fails, the MCP server still works (it'll index
on first query) — just slower.

The `bmad-dev-story` prompt explicitly tells the dev subprocess to use these
MCPs **before reaching for Read**, with `Read` only via `offset+limit` when
the symbol body itself is needed. This is the primary token-saving lever for
large monorepos.

## PR Group (phase 04)

One PR per involved repo, all on branch `feat/oracle-project-<slug>`, all
labeled with `oracle-project`, `group:project-<slug>`, and the original
`project: <Name>` label. PR body includes:

> Tracking issue: <org>/the-oracle-backlog#<N>
> **Do not merge until all PRs in this group are approved.**

Push uses `--force-with-lease` so resumed runs can safely rewrite history if
the dev workflow rewrote a commit.

After all PRs are open, the anchor issue is flipped to `maestro:deploying`
and a `repository_dispatch` event (`oracle.project.complete`) fires at
`<org>/infra` with the slug, anchor number, repo list, and context path.

## Notification Webhook (phase 05)

If `NOTIFICATION_WEBHOOK_URL` is set, phase 05 POSTs:

```json
{
  "event": "oracle.pipeline.complete",
  "project_slug": "<slug>",
  "project_name": "<name>",
  "anchor_issue": <int>,
  "hard_failures": <int>,
  "prs": [{"repo": "...", "url": "..."}, ...]
}
```

The POST is fire-and-forget — failures never abort the pipeline.

## Concurrency

The pipeline allows up to **2** concurrent runs. Phase 02 counts open
`maestro:implementing` issues; if `> 2`, it exits 0 with the label intact so
a future run picks it up.

## Parallel Run Mode

### Wave algorithm
[`scripts/plan-waves.py`](scripts/plan-waves.py) implements greedy first-fit
graph coloring:

```
For each story s in BMAD order:
  modules(s) := tokenized lowercase set from STORY_AFFECTED_MODULES
  For each existing wave w:
    if forall t in w: modules(s) ∩ modules(t) == ∅:
      append s to w
      goto next story
  open new wave [s]
```

The result is **deterministic** (stable across reruns) and **preserves epic
ordering** within each wave. Output `waves.txt` has one line per wave;
records within a line are tab-separated, fields are pipe-separated:

```
EPIC|STORY|TITLE|module1,module2  <TAB>  EPIC|STORY|TITLE|module3,module4 ...
```

### Workspace isolation
Each parallel agent gets its own `/tmp/oracle-work-<i>/` provisioned by
`cp -r /tmp/oracle-work` in main context **before** spawning. The agent runs
[`scripts/run-wave-story.sh`](scripts/run-wave-story.sh) which symlinks
`/tmp/oracle-work` → `ORACLE_WORK` so the rest of the pipeline scripts work
unchanged.

The `Task` tool's `isolation: "worktree"` adds a git-level worktree on top —
agent commits land in its own branch, then main rebases-and-merges into the
canonical feature branch once the wave drains.

### Merge protocol (per wave)
1. Await all agents in the wave (`TaskOutput` with `block: true` per agent).
2. Validate each agent's last-line JSON for `status: ok`.
3. For each successful agent, fetch its commit and cherry-pick onto the
   canonical `feat/oracle-project-<slug>` branch.
4. Conflicts → fail the wave, increment `HARD_FAILURES`, fall back to
   sequential mode for the remaining stories.

### Failure handling differences from sequential mode
- A halted agent is treated as one `HARD_FAILURE` (no per-agent retry —
  retries happen inside `03-run-story.sh` already).
- Cherry-pick conflict in main context = automatic fall-back to sequential
  mode for remaining waves; the wave that conflicted gets re-run sequentially.
- The `HARD_FAILURES ≥ 5` runaway guard still applies.

### When the wave plan degenerates
If `plan-waves.py` produces N waves of 1 story each, parallel mode offers
no speedup — main context should detect this (compare wave count to story
count) and fall through to sequential mode.

## Adding a Phase

1. Add a script `scripts/NN-<name>.sh` reading prior `env.0N.sh` files.
2. Append a row to the SKILL.md "Scripts" table.
3. Add the failure mode to SKILL.md "Error Handling".
4. Update this REFERENCE.md state machine if labels or transitions change.

## Migrating from the Old Shard Layout

The old layout had `shards/phase-{00..05}-*.md` with bash blocks Claude
copy-pasted into Bash tool calls. That cost ~900 tokens per run just to
re-read the bash. The current layout moves bash into executable scripts:

| Old shard | New script |
|-----------|------------|
| `shards/phase-00-input.md` | `scripts/00-discover-anchor.sh` |
| `shards/phase-01-workspace.md` | `scripts/01-setup-workspace.sh` |
| `shards/phase-02-repos.md` | `scripts/02-prepare-repos.sh` |
| `shards/phase-03-story-loop.md` | `scripts/03-run-story.sh` (per-story) + main loop in SKILL.md |
| `shards/phase-04-pr-group.md` | `scripts/04-open-prs.sh` |
| `shards/phase-05-output.md` | `scripts/05-finalize.sh` |

Behavior is preserved byte-identical except for added quality gates
(lint-check, check-coverage, pre-commit-check) borrowed from the BMAD
`developer` skill.
