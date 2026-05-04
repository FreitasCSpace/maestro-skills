# Maestro Skills — Subagent Patterns

Canonical parallelization patterns shared across all maestro skills. Adapted
from `aj-geddes/claude-code-bmad-skills` and tightened for the Oracle pipeline.

## Core Principle

**Never do sequentially what can be done in parallel.** Each skill should
decompose its work into independent subtasks, fan them out to subagents, then
synthesize results in main context.

## Subagent Types

Invoke via the `Task` tool. Pick the smallest-capability agent that can do
the job — fewer tools = faster startup and tighter context.

| `subagent_type`   | Tools                          | Best for |
|-------------------|--------------------------------|----------|
| `Explore`         | Read, Grep, Glob (read-only)   | Fast codebase exploration |
| `Plan`            | Read-only                      | Architecture, design decisions |
| `general-purpose` | All tools                      | Implementation, multi-step tasks |

Pass `isolation: "worktree"` when an agent will write code AND another agent
might touch overlapping files. Pass `run_in_background: true` for fan-out.

## Pattern 1 — Fan-Out Research

Several independent questions, one synthesizer.

```
Main → spawn N background agents (different queries)
Main → continue or wait for all
Main → read each agent's output file → synthesize
```

**Use when:** investigating multiple unrelated subjects (market, competitors,
tech feasibility, user research).

## Pattern 2 — Parallel Section Generation

One document, several sections, each section drafted by a different agent.

```
Main → write shared context file
Main → spawn one agent per section (with section-specific prompt)
Main → assemble document by concatenating section outputs
```

**Use when:** generating PRDs, architecture docs, sprint plans.

## Pattern 3 — Story Parallel Implementation (Oracle Pipeline)

Independent stories implemented concurrently in worktree-isolated agents.

```
Main → run plan-waves.py to compute parallel-safe waves
Main → for each wave:
         spawn one agent per story with isolation: worktree
         each agent runs scripts/03-run-story.sh inside its worktree
         each agent commits to the same feature branch (rebase-safe)
         await all agents in the wave
Main → continue to next wave once current wave drains
```

**Story independence rule:** two stories are wave-compatible iff their
`STORY_AFFECTED_MODULES` sets do not overlap.

**Use when:** project has 2+ stories with disjoint module scopes.
**Don't use when:** all stories touch the same files (file-level conflicts).

## Pattern 4 — Component Parallel Design

One agent per system component (auth, data, API, UI), each producing its own
design doc; main context integrates.

## Pattern 5 — Per-Repo Fan-Out

Multi-repo operations (lint, coverage, audit) run as one agent per repo.
Use when the per-repo work is heavy and independent.

## Subagent Prompt Template

Every spawned agent gets a fresh context window. The prompt MUST be
self-contained.

```markdown
## Task
[One sentence — what this agent does]

## Context
[All relevant facts — paths, names, constraints. The agent cannot see main.]
- Project: {{project_slug}}
- Repo: {{repo_root}}
- Story: {{story_key}}

## Objective
[Concrete, single-purpose goal]

## Deliverables
1. [Concrete output 1]
2. [Concrete output 2]

## Output
Write results to: {{output_file}}
Last line MUST be JSON: {"status":"...","..."}
```

## Coordination Strategies

### Shared context via files
Before fan-out, write the shared facts to a file (e.g.
`/tmp/oracle-work/wave-N.context.md`); each agent reads it, writes to a
unique output path.

### Dependency tiers
If some agents depend on others' outputs, run in tiers:

```
Tier 1 (parallel):  A, B, C
                  └─ wait all
Tier 2 (parallel):  D (needs A), E (needs B,C)
                  └─ wait all
Tier 3 (sequential): synthesize in main
```

### Result collection
Spawn with `run_in_background: true`, then `TaskOutput` with `block: true`
when ready to collect. Continue main work in between if you have any.

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Spawn agents for trivial tasks (<1K tokens of work) | Setup cost > work |
| Pass entire conversation history into a prompt | Wastes context budget |
| Chain subagents 3+ deep | Fan-in becomes intractable |
| Parallelize tasks with file-level conflicts | Worktrees won't save you on merge |
| Spawn one agent per file | Bundle related files into one agent |

## Integration with Oracle Pipeline

The oracle-pipeline `SKILL.md` documents two run modes:

- **Sequential** (default) — `03-run-story.sh` per story, in main context
- **Parallel waves** — `plan-waves.py` groups stories by module-disjointness,
  then main context fans out one Task agent per story per wave

See `skills/oracle-pipeline/REFERENCE.md#parallel-run-mode` for the wave
algorithm and merge protocol.
