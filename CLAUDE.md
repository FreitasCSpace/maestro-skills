# ClaudeHub Skills Repository

This repository contains skill definitions for ClaudeHub — a Claude Code skill orchestrator.

## How Skills Work

Each skill is defined in `.claudehub.yml` and represents an autonomous Claude Code session.
When triggered from ClaudeHub, the skill prompt is sent to `claude -p` which executes it
with full tool access (Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch).

## Skill Types

- **SEO & Content** — Site audits, keyword research, blog writing, content briefs
- **Code & Security** — Code review, dependency audit, test generation
- **Documentation** — README generation, API docs
- **DevOps** — Dockerization, CI/CD pipeline generation
- **Marketing** — Social content, competitor analysis, landing pages
- **Data & Research** — Codebase analysis, migration planning

## Adding New Skills

Add entries to `.claudehub.yml`:

```yaml
skills:
  - name: my-skill-name
    description: What this skill does
    prompt: "The instruction sent to Claude Code"
    max_turns: 20
```

### Placeholders

Use `{variable}` in prompts — ClaudeHub will prompt for these when triggering a run:

```yaml
prompt: "/seo-audit {url}"          # User provides the URL
prompt: "Migrate to {target}"       # User provides target framework
```

### Slash Commands

Skills can invoke any Claude Code skill/slash command:

```yaml
prompt: "/seo-technical {url}"      # Invokes the seo-technical skill
prompt: "/write-blog {keyword}"     # Invokes the write-blog skill
```

## Running Skills

1. Connect this repo in ClaudeHub → Repositories
2. ClaudeHub auto-detects skills from `.claudehub.yml`
3. Go to Runs → trigger any skill
4. Skills can be scheduled via cron, webhook, or chain triggers
