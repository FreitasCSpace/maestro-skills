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

Autonomous project-level dev pipeline. Unit of work: every epic and user story
sharing a `project:<name>` label, executed in BMAD dependency order, no
per-story human gate. Trigger surface: open user-story issues with
`project:<X>` + `maestro-ready` labels. Anchor issue = lowest-numbered open
story in the group. All orchestration comments go on the anchor issue.

`CARESPACE_CONTEXT.md` is ~47KB — **never read the full file.** The scoped
read (involved repos only) happens in phase-02-bmad-context.md after
`involved_repos` is known.

**CRITICAL: Your very first action is reading `shards/phase-00-input-gate.md`.
Do NOT read any other file first. Do NOT look at PIPELINE.md. Every run is a
brand new project.**

---

## Shard Reading Map

Read each shard at the moment you enter that phase. Never pre-load.

| When to read                     | Shard                          |
|----------------------------------|--------------------------------|
| **FIRST** (before anything else) | shards/phase-00-input-gate.md  |
| After 0.1 succeeds               | shards/phase-01-workspace.md   |
| After anchor resolved (0.4)      | shards/phase-02-bmad-context.md|
| After 0.5b (involved_repos known)| shards/phase-03-repos.md       |
| After 0.10 (PIPELINE.md written) | shards/phase-04-bootstrap.md   |
| Before first story               | shards/phase-05-story-loop.md  |
| On any hard failure              | shards/phase-06-failure.md     |
| After last story completes       | shards/phase-07-scope-audit.md |
| After scope audit                | shards/phase-08-pr-group.md    |
| After all PRs opened             | shards/phase-09-deploy.md      |
| After deploy dispatch            | shards/phase-10-output.md      |

All shards are in `~/.claude/skills/oracle-pipeline/shards/`.

---

## Anti-Waste Rules (active for the entire run)

1. **Never re-read a file you already read.** Once in context: done.
   Applies to context-scoped.md, BMAD files, PIPELINE.md, source files.
2. **Never re-read PIPELINE.md unless you wrote to it.** You wrote it; you know it.
3. **Never re-explore the codebase between stories.** Use `affected_modules`
   and `new_files_needed` from the story — don't re-grep.
4. **Use BMAD context, not blind exploration.** If feature-intent.json or the
   story already told you about a file, go directly.
5. **One search per question.** Pick the best grep. One alternative — move on.
6. **Auto-discovery is exactly ONE `gh issue list` call.** Do not wander.

## Iteration Guard (global)

- Single story: max 3 inline fix attempts → hard failure (Phase 1.5).
- Whole project: max 5 hard story failures → abort `PIPELINE_RUNAWAY`.
