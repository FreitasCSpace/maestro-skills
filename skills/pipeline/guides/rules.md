# Pipeline Rules

## Exploration Best Practices

1. **Grep before read.** Verify a file is relevant before reading it.
2. **Read the codebase map first.** `.pipeline/CODEBASE_MAP.md` tells you
   where things are.
3. **Use sub-agents for broad exploration.** Spawn `Explore` sub-agents in
   parallel — their context is separate.
4. **Read files partially when possible.** Use offset/limit or grep.
5. **Never blindly traverse directories.** Use grep/find with patterns.

## Binary Files

**NEVER use WebFetch on image/binary URLs** (.png, .jpg, .pdf, etc.).
Download via `curl`, then view with the Read tool.

## Context Management

If the conversation is getting long:
1. Summarize completed phases in PIPELINE.md
2. PIPELINE.md IS your memory
3. Continue with the next phase

## Iteration Guard

If review, security, or QA finds issues and you've already fixed 3 times:
- Update `## Status` to `NEEDS_HUMAN`
- Commit and push
- Stop: "Pipeline needs human review after 3 fix iterations"

## Completion Gate (MANDATORY)

**You are NOT done until a PR exists.** Before outputting the final result:

1. Verify a PR was created: `gh pr list --head $(git branch --show-current) --json url`
2. If no PR exists, go back and complete the work
3. If you cannot complete the task, output `FAILED:` not `COMPLETE:`

**NEVER report success without a PR URL.**
