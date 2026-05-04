# the-oracle-story-dev — Reference

## Quick commands

### List stories in a feature
```bash
python3 scripts/parse-stories.py \
  --backlog /tmp/the-oracle-backlog \
  --feature provider-patient-feedback-communication \
  --list
```

### Initialize sprint manifest
```bash
python3 scripts/sprint-status.py init \
  --manifest ~/.bmad-sprint/provider-patient-feedback-communication.yaml \
  --backlog /tmp/the-oracle-backlog \
  --feature provider-patient-feedback-communication
```

### Show sprint board
```bash
python3 scripts/sprint-status.py show --manifest <path>
```

### Mark a story
```bash
python3 scripts/sprint-status.py set \
  --manifest <path> --story 2.4 --status Done \
  --pr-urls "https://…/pull/12,https://…/pull/34"
```

### Open PRs (after branches pushed)
```bash
bash scripts/multigitter-pr.sh \
  --workspace /tmp/oracle-work \
  --branch bmad/provider-patient-feedback-communication/story-2.4 \
  --story-json /tmp/story.json \
  --base develop
```

## Story schema

The skill expects `stories-output.md` files in
`<backlog>/bmad-context/<feature>/stories-output.md` with:

- YAML frontmatter at top (`repos_affected`, `feature`, etc.)
- Epic headers: `### Epic N: <title>`
- Story headers: `#### Story N.M: <title>`
- Each story block contains `**User outcome:**`, `**Acceptance Criteria:**`
  (bullet list), and `FR-NNN` references.

## Sprint manifest schema

See `templates/sprint-status.yaml`. Statuses:
`Ready` → `InProgress` → `Review` → `Done` (+ `Blocked`).

Manifests live in `${WORKSPACE:-/tmp/oracle-work}/.bmad-sprint/<feature>.yaml`
— **never** written back into the backlog repo.

## Branch naming

`bmad/<feature-slug>/story-<epic.story>` — same name across every repo in
`repos_affected`, which is what enables multi-gitter to fan out PRs.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `parse-stories.py: story X not found` | wrong feature slug or stories-output.md missing | `--list` to enumerate, verify slug |
| `multi-gitter: command not found` | binary not installed | wrapper auto-falls-back to per-repo `gh pr create` |
| PR creation 422 "no commits" | branch pushed but identical to base | verify Build phase actually committed |
| `manifest not initialized` | skipped Step 1 init | run `sprint-status.py init` |
| Story has empty `repos_affected` | malformed frontmatter in stories-output.md | open backlog issue against `the-oracle-backlog` |

## Boundary with `the-oracle-development`

| Trigger | Use |
|---|---|
| Input is a GitHub issue URL | `the-oracle-development` |
| Input is a BMAD story ID + feature slug | `the-oracle-story-dev` |
| Input mentions "next story" or "sprint" | `the-oracle-story-dev` |
| Input mentions "fix bug X" or "issue 146" | `the-oracle-development` |
