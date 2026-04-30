# Phase 05 — Per-Story gstack Loop

For each story in BMAD dependency order (from `stories-output.md`), execute
the full gstack pipeline scoped to **that one story**. Each story is its own
mini-pipeline inside the project run.

Read each gstack SKILL.md head-100 **once per project run** (not once per
story). Keep them in context for all stories.

```
for story in stories-output.md (BMAD order):
```

### 1.0 Pick up the story

```bash
# Transition this story's issue: maestro-ready → oracle:implementing
gh issue edit <story_issue_number> \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --add-label oracle:implementing \
  --remove-label maestro-ready
```

Only the current story's issue changes label. All other stories remain
`maestro-ready` until their turn.

Append `### Story <N.M> — <title>` to PIPELINE.md with `## Status: IN_PROGRESS`.

### 1.1 Investigate

```bash
head -100 ~/.claude/skills/gstack/investigate/SKILL.md
```

For each repo in REPOS (repos touched by this story's SCOPE):
- `cd workspace/<repo>`
- Follow gstack investigate methodology scoped to `story.affected_modules`
- Do NOT explore beyond SCOPE
- Record approach in PIPELINE.md `### Story <N.M> / ## Investigation`

### 1.2 Think

```bash
head -100 ~/.claude/skills/gstack/office-hours/SKILL.md
```

Apply the six forcing questions to the story's acceptance criteria.
Append `## Think` to the story's PIPELINE.md section.

### 1.3 Plan

```bash
head -100 ~/.claude/skills/gstack/plan-eng-review/SKILL.md
```

Lock the per-repo edit plan. Verify every planned file is in SCOPE — if a
planned file is outside SCOPE, drop it or flag as scope deviation now (not
post-build). Append `## Plan` to the story section.

### 1.4 Build

For each repo in REPOS:
```bash
cd workspace/<repo>
# Apply plan via Edit / Write
# Run project test command (from CLAUDE.md)
# If tests fail and fixable inline: fix and re-run (max 2 attempts per story per repo)
```

Capture `git diff HEAD` — every modified path MUST be in SCOPE.
Out-of-scope paths → append to project `scope_deviations[]` (does NOT block
the story).

### 1.5 Review

```bash
head -100 ~/.claude/skills/gstack/review/SKILL.md
```

Run gstack review on the per-story diff (NOT the cumulative diff). Max 3 fix
iterations per story. If review fails after 3 iterations → **hard story
failure** (read `shards/phase-06-failure.md`).

### 1.6 Security (conditional)

If `story.affected_modules` touches any HIPAA path (Profile, Client,
Evaluation, Survey, Auth, Storage):

```bash
head -100 ~/.claude/skills/gstack/cso/SKILL.md
```

Run OWASP Top 10 + STRIDE audit on the per-story diff. Apply confidence gate
(8/10+) and false-positive exclusions per the gstack skill.

If a critical vuln is found: fix, re-audit (max 2 iterations). Unfixable
after 2 → **hard story failure** (read `shards/phase-06-failure.md`).

If no HIPAA path touched: skip and note in PIPELINE.md.

### 1.7 QA

```bash
head -100 ~/.claude/skills/gstack/qa/SKILL.md
```

Run automated tests for each touched repo. Visual/browser tests only if the
story explicitly requires UI verification (UX-DR acceptance criteria). If a
bug is found: fix, generate regression test, re-verify.

### 1.8 Atomic commit (per repo)

```bash
for REPO in REPOS:
  cd workspace/<repo>
  git add -A
  git commit -m "[Story <N.M>] <story title>"
```

Do NOT push yet — push happens once at the end of the run (Phase 3).

### 1.9 Bookkeeping

```bash
# Transition this story's issue: oracle:implementing → oracle:story-done
gh issue edit <story_issue_number> \
  --repo "$TARGET_ORG/the-oracle-backlog" \
  --add-label oracle:story-done \
  --remove-label oracle:implementing
```

Update PIPELINE.md story section `## Status: COMPLETE`.

---

## Iron Law

Every commit diff must be a strict subset of SCOPE (story's
`affected_modules` + `new_files_needed`). Out-of-scope edits accumulate in
`scope_deviations[]` — they do NOT fail the story, but they DO cause the
resulting PRs to carry `scope-deviation` label and skip auto-deploy.

**Why per-story gstack (not per-project):** per-story keeps investigation,
review, and security audit focused on each unit's own diff and acceptance
criteria. Cumulative review drowns the reviewer in a 20-file diff.

---

**On hard failure at any step:** read `shards/phase-06-failure.md`

**After last story completes:** read `shards/phase-07-scope-audit.md`
