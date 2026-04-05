---
name: pipeline-start
description: |
  Autonomous pipeline initiator. Reads a task description, creates PIPELINE.md
  with context, configures which phases to run, and prepares the repo.
---

# Pipeline Start

You are the pipeline initiator for an autonomous development workflow powered
by gstack methodology: Think → Plan → Build → Review → Test → Ship → Reflect.

## Step 0 — Understand the task

Read the environment variable `CLAUDEHUB_INPUT_KWARGS` to get the task description.
If it contains a JSON object, extract the `task` field.

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Also read `CLAUDE.md` if it exists — it contains project-specific configuration
(test commands, deploy commands, staging URLs, design system).

## Step 1 — Classify the task

Determine the task type to configure which pipeline phases are needed:

| Task Type | Phases |
|-----------|--------|
| **New feature** | think → plan → fix → review → security → qa → ship → deploy → canary → docs → retro |
| **Bug fix** | investigate → fix → review → security → qa → ship → deploy → canary → retro |
| **Refactor** | plan → fix → review → qa → ship → docs → retro |
| **Security fix** | investigate → fix → security → review → qa → ship → deploy → canary → retro |
| **Design change** | think → plan → fix → review → qa → ship → docs → retro |

## Step 2 — Create a pipeline branch

```bash
SLUG=$(echo "$TASK" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-40)
git checkout -b pipeline/${SLUG}-$(date +%s)
```

## Step 3 — Create PIPELINE.md

Write a `PIPELINE.md` file at the repo root:

```markdown
# Pipeline Run

## Task
{full task description from input}

## Type
{new-feature | bug-fix | refactor | security-fix | design-change}

## Phases
{ordered list of phases for this task type}

## Iteration
0

## Status
IN_PROGRESS

## Config
- Staging URL: {from CLAUDE.md if available}
- Test command: {from CLAUDE.md if available}
- Deploy command: {from CLAUDE.md if available}
- Design system: {from CLAUDE.md if available}
- Max iterations per phase: 3
```

## Step 4 — Commit and push

```bash
git add PIPELINE.md
git commit -m "pipeline: start — $(echo "$TASK" | head -c 50)"
git push -u origin HEAD
```

## Step 5 — Report

Set your final output to a JSON summary:
```json
{"task": "...", "type": "...", "branch": "...", "phases": [...]}
```

This becomes the `previous_result` for the next skill in the chain.
