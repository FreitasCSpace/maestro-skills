# Maestro Shared Helpers

Reusable patterns referenced from individual skills. Each entry is a named
recipe — link to it from a skill instead of duplicating the steps.

## Subagent Operations

### Launch-Parallel-Agents
```
Purpose: Spawn N independent agents for fan-out work
Pattern:
  1. Write shared context to /tmp/<run>/context.md
  2. For each task i = 1..N:
       Task tool with:
         subagent_type: "general-purpose" | "Explore" | "Plan"
         run_in_background: true
         isolation: "worktree"   # only if writing files
         prompt: <self-contained prompt referencing the context file
                  and a unique output path /tmp/<run>/agent-i.out>
  3. Return list of agent IDs
```

### Collect-Agent-Results
```
Purpose: Drain background agents
Pattern:
  1. For each agent ID:
       TaskOutput with block: true
  2. Read each agent's output file
  3. Validate the JSON status line
  4. Return collected results
```

### Synthesize-Results
```
Purpose: Merge N agent outputs in main context
Pattern:
  1. Read each agent output
  2. Detect overlaps and conflicts (same file path, same record)
  3. Prefer the agent with more detailed output, or ask user on tie
  4. Write merged document to canonical location
```

## File / Repo Operations

### Detect-Default-Branch
```
Purpose: Resolve a repo's main/master/trunk dynamically
Pattern:
  DEFAULT=$(git remote show origin 2>/dev/null \
            | grep 'HEAD branch' | awk '{print $NF}')
  DEFAULT="${DEFAULT:-master}"
```

### Skip-If-Already-Committed
```
Purpose: Make resumable loops idempotent on commit subjects
Pattern:
  DONE=$(git log "origin/$DEFAULT..$BRANCH" --format=%s \
         | grep -oE '\[Story [A-Za-z0-9._-]+\]' \
         | sed 's/\[Story //;s/\]//')
  for sk in $DONE; do COMPLETED+=("$sk"); done
```

## Quality Gates

### Run-Lint
See `skills/oracle-pipeline/scripts/lint-check.sh` — auto-detects
npm/eslint/ruff/flake8/go vet.

### Run-Coverage
See `skills/oracle-pipeline/scripts/check-coverage.sh` — auto-detects
jest/pytest/go test, threshold via `COVERAGE_THRESHOLD` (default 80).

### Pre-Commit
See `skills/oracle-pipeline/scripts/pre-commit-check.sh` — runs both
gates as a final guard before staging.

## Token Optimization

### Reference-Pattern
```
✓ "Follow shared/helpers.md#Skip-If-Already-Committed"
✗ <inline 10-line bash block in every skill>
```

### Lazy-Loading
```
1. Skills load SKILL.md only by default (~3K tokens)
2. REFERENCE.md is opened only when debugging or extending
3. Bulk context (e.g. resources/carespace-context.md) is opt-in
```

### Scripts Over Markdown Bash Blocks
Bash that runs the same way every time belongs in `scripts/*.sh`, not in
SKILL.md. Calling `bash scripts/foo.sh` costs zero tokens for the script
contents — Read'ing the same bash from a markdown shard tokenizes the
whole block.
