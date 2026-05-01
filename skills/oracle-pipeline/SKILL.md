---
name: oracle-pipeline
description: |
  Autonomous BMAD implementation pipeline. Reads epics and stories from an
  existing BMAD context in the-oracle-backlog, implements each story using
  bmad-create-story → bmad-dev-story → bmad-code-review subprocesses, commits
  per story, and opens one cumulative PR per affected repo. One anchor GitHub
  issue tracks the whole project — no per-story issues needed.
---

# Oracle Pipeline (BMAD-based)

Implements an entire Oracle backlog project using BMAD's own dev workflows.
Trigger surface: ONE anchor issue per project carrying `project:<name>` +
`maestro-ready`. All progress is tracked via comments on that single issue.

**CRITICAL: First action is reading `shards/phase-00-input.md`. Nothing else.**

---

## Shard Reading Map

| When to read                      | Shard                        |
|-----------------------------------|------------------------------|
| **FIRST** (before anything else)  | shards/phase-00-input.md     |
| After anchor issue resolved       | shards/phase-01-workspace.md |
| After stories-index built         | shards/phase-02-repos.md     |
| Before first story                | shards/phase-03-story-loop.md|
| After last story committed        | shards/phase-04-pr-group.md  |
| After PRs opened                  | shards/phase-05-output.md    |

All shards at `~/.claude/skills/oracle-pipeline/shards/`.

---

## Anti-Waste Rules

1. Never re-read a file already in context.
2. `stories-index.md` is read ONCE — never re-read it mid-loop.
3. Never re-read PIPELINE.md unless you just wrote to it.
4. `claude --print` output is captured in a variable — don't re-run to see it.
5. One search per question — pick the best grep, move on.

## Iteration Guard

- Per story: if `bmad-dev-story` halts twice → post failure on anchor issue, label `oracle:blocked-pipeline-failed`, exit.
- Whole project: >5 story failures → `PIPELINE_RUNAWAY`, exit.
