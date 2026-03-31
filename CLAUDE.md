# ClaudeHub SecDevOps Skills

3 skills following the OOP skill pattern from [agente-skill-oop](https://github.com/gugastork/agente-skill-oop):

| Skill | Type | Role |
|-------|------|------|
| **code-standards-base** | Abstract/Reference | CareSpace security standards — HIPAA, OWASP, Azure. Not invoked directly. |
| **security-auditor** | Specialist | Detects vulnerabilities by file type using the standards checklist. |
| **code-review-orchestrator** | Orchestrator | Autonomous PR review — fetches diff, runs audit, posts PR comment. |

## How It Works

The **orchestrator** is the entry point. It embeds the standards + auditor logic and runs fully autonomously:

1. Fetches PR diff via `gh` CLI
2. Classifies files (backend/frontend/mobile/infra)
3. Applies security audit checklist per file type
4. Checks code quality
5. Scores: BLOCK / NEEDS CHANGES / PASS
6. Posts review as PR comment

## Required Secrets

- `GITHUB_TOKEN` — for PR diff fetching and comment posting
