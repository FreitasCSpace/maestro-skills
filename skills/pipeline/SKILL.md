---
name: pipeline
description: |
  Autonomous dev pipeline — runs the full gstack sprint in one session.
  Auto-detects project stack, installs deps, generates temp CLAUDE.md if missing.
  Reads actual gstack SKILL.md files for full methodology.
---

# Autonomous Dev Pipeline

You are an autonomous development pipeline. You execute the full gstack sprint
in this single session — from understanding the task to shipping a PR.

**CRITICAL FIRST STEP — DO THIS BEFORE ANYTHING ELSE:**

Any files in the current working directory are STALE from a previous pipeline
run. Do NOT read them. Do NOT look at PIPELINE.md. Do NOT assume any work is
done. This is a BRAND NEW task. Ignore everything in the current directory.

Your very first action must be to read the task input and clone a fresh repo.
NEVER say "already completed" — every run is a new task.

## Tool Loading Strategy (saves context)

This session runs with `ENABLE_TOOL_SEARCH=true`. Tools and skills are NOT
pre-loaded into context. You must use the `ToolSearch` tool to find what you
need when you need it.

**Only load tools/skills for the phase you're currently executing.** Don't
pre-load everything upfront. Examples:

- Setup phase: you already have Bash, Read, Write — no ToolSearch needed
- Investigation phase: `ToolSearch` for "Grep Glob" or specific MCP tools if needed
- Build phase: load Edit tool — `ToolSearch` with `"select:Edit"` when you
  first need to modify a file
- QA phase: `ToolSearch` for "browser playwright" only if visual testing is needed

Reading gstack SKILL.md files via `cat` does NOT use ToolSearch — those are
just file reads. ToolSearch is only for loading deferred tool schemas.

---

## CareSpace Codebase Context (READ THIS FIRST)

Before doing anything, read the CareSpace codebase context. It tells you which
repo handles what, the architecture, conventions, and where to look for issues
by type. This is the most efficient way to orient yourself.

```bash
cat ~/.claude/skills/pipeline/CARESPACE_CONTEXT.md
```

This file contains:
- What CareSpace is (HIPAA healthcare platform)
- All 11 active repos and their stacks
- Bug tracker issue body format (Codebase Context, Claude Code Fix Instructions sections)
- Frontend (carespace-ui) atomic design + path aliases + Redux slices + routes
- Backend (carespace-admin) NestJS modules + Prisma + auth
- Posture engine, 3D body service, Strapi CMS, mobile apps, SDK
- "Where to look by issue type" tables for each repo
- HIPAA / PHI / audit log requirements

After reading, you'll know exactly which repo + folder to clone and focus on.

---

## Step 0 — Setup

### Read task input

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Extract the `task` field. This is YOUR task for THIS run. It has NOT been done yet.

### Authenticate GitHub

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status
```

### Understand the task and clone the CORRECT repo

**CRITICAL:** You MUST work on the repo referenced in the task, NOT whatever
repo is already in the working directory. The working directory may contain
a repo from a previous pipeline run — IGNORE IT.

Extract the repo owner/name from the task. If the task contains a GitHub issue
URL like `https://github.com/carespace-ai/carespace-admin/issues/146`, the
repo is `carespace-ai/carespace-admin`.

```bash
# Parse repo from issue URL in the task
TASK=$(echo "$CLAUDEHUB_INPUT_KWARGS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task',''))")
REPO=$(echo "$TASK" | grep -oP 'github\.com/\K[^/]+/[^/]+' | head -1)
echo "Target repo: $REPO"
```

**ALWAYS clone the target repo fresh into a clean directory.** The working
directory may contain files from a previous pipeline run — wipe everything.

```bash
# MANDATORY: Nuke previous run data completely
rm -rf /tmp/pipeline-work 2>/dev/null
mkdir -p /tmp/pipeline-work
cd /tmp/pipeline-work

# Clone the CORRECT repo fresh (shallow — large repos fail full clone)
gh repo clone "$REPO" . -- --depth=50 2>&1

# Delete any stale PIPELINE.md from previous pipeline runs committed to the repo
rm -f PIPELINE.md 2>/dev/null
```

**IMPORTANT:** You MUST work in `/tmp/pipeline-work` for the entire run.
ALL subsequent bash commands must run in this directory.

Now fetch the issue details:

```bash
ISSUE_NUM=$(echo "$TASK" | grep -oP 'issues/\K\d+')
gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body,labels,state
```

**DO NOT download or read screenshots.** Issue screenshots cause the session
to hang (large images take 60+ seconds via the Read tool API, causing apparent
freezes). The issue text description contains all the information needed to
investigate and fix the bug. Ignore any image URLs in the issue body.

### Configure git for the cloned repo

```bash
git config user.email "pipeline@carespace.ai"
git config user.name "CareSpace Pipeline"
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git"
```

### Auto-detect project stack and install dependencies

Detect the project type and install dependencies automatically. Run the
appropriate commands based on what files exist:

```bash
# Detect and install
if [ -f "package-lock.json" ]; then
  echo "Node.js (npm) detected"
  npm install --legacy-peer-deps 2>&1 | tail -5
elif [ -f "yarn.lock" ]; then
  echo "Node.js (yarn) detected"
  npm install --legacy-peer-deps 2>&1 | tail -5
elif [ -f "bun.lock" ] || [ -f "bun.lockb" ]; then
  echo "Node.js (bun) detected"
  bun install 2>&1 | tail -5
elif [ -f "package.json" ]; then
  echo "Node.js detected"
  npm install --legacy-peer-deps 2>&1 | tail -5
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  echo "Android/Gradle detected"
  # Gradle projects — skip install, build phase handles it
elif [ -f "go.mod" ]; then
  echo "Go detected"
  go mod download 2>&1 | tail -5
elif [ -f "requirements.txt" ]; then
  echo "Python detected"
  pip install -r requirements.txt 2>&1 | tail -5
elif [ -f "pyproject.toml" ]; then
  echo "Python (pyproject) detected"
  pip install -e . 2>&1 | tail -5
elif [ -f "pubspec.yaml" ]; then
  echo "Dart/Flutter detected"
  flutter pub get 2>&1 | tail -5
elif [ -f "Gemfile" ]; then
  echo "Ruby detected"
  bundle install 2>&1 | tail -5
else
  echo "Unknown project type — no auto-install"
fi
```

### Read or generate project config

Read `CLAUDE.md` if it exists. If it does NOT exist, auto-generate a temporary
one based on the detected project type. This tells all downstream phases how to
build, test, and lint.

If `CLAUDE.md` does not exist, create it:

```bash
if [ ! -f "CLAUDE.md" ]; then
  # Auto-detect commands from package.json / build files
  if [ -f "package.json" ]; then
    TEST_CMD=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('scripts',{}).get('test',''))" 2>/dev/null)
    BUILD_CMD=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('scripts',{}).get('build',''))" 2>/dev/null)
    LINT_CMD=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('scripts',{}).get('lint',''))" 2>/dev/null)
    START_CMD=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('scripts',{}).get('start',d.get('scripts',{}).get('dev','')))" 2>/dev/null)
    FRAMEWORK=$(python3 -c "import json; d=json.load(open('package.json')); deps=list(d.get('dependencies',{}).keys())+list(d.get('devDependencies',{}).keys()); fw=[k for k in deps if k in ['react','next','@nestjs/core','express','vue','@angular/core','svelte']]; print(', '.join(fw) if fw else 'node')" 2>/dev/null)
    cat > CLAUDE.md << GENEOF
# $(basename $(pwd))

## Framework
$FRAMEWORK

## Commands
\`\`\`bash
npm install --legacy-peer-deps   # install dependencies
${TEST_CMD:+npm test                        # run tests}
${BUILD_CMD:+npm run build                   # build}
${LINT_CMD:+npm run lint                    # lint}
${START_CMD:+npm start                       # dev server}
\`\`\`

## Generated by Maestro Pipeline
This CLAUDE.md was generated by the Maestro autonomous pipeline to document
project commands and conventions. Feel free to edit and expand it. It will be removed before PR creation.
GENEOF
  elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    cat > CLAUDE.md << 'GENEOF'
# Android Project

## Commands
```bash
./gradlew assembleDebug    # build debug
./gradlew test             # run unit tests
./gradlew lint             # run lint
./gradlew connectedCheck   # run instrumented tests (requires device)
```

## Generated by Maestro Pipeline
This CLAUDE.md was generated by the Maestro autonomous pipeline to document
project commands and conventions. Feel free to edit and expand it.
GENEOF
  elif [ -f "go.mod" ]; then
    cat > CLAUDE.md << 'GENEOF'
# Go Project

## Commands
```bash
go build ./...      # build
go test ./...       # run tests
go vet ./...        # lint
```

## Generated by Maestro Pipeline
This CLAUDE.md was generated by the Maestro autonomous pipeline to document
project commands and conventions. Feel free to edit and expand it.
GENEOF
  elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    cat > CLAUDE.md << 'GENEOF'
# Python Project

## Commands
```bash
pytest               # run tests
python -m mypy .     # type check
ruff check .         # lint
```

## Generated by Maestro Pipeline
This CLAUDE.md was generated by the Maestro autonomous pipeline to document
project commands and conventions. Feel free to edit and expand it.
GENEOF
  elif [ -f "pubspec.yaml" ]; then
    cat > CLAUDE.md << 'GENEOF'
# Flutter/Dart Project

## Commands
```bash
flutter pub get      # install deps
flutter test         # run tests
flutter analyze      # lint
flutter build        # build
```

## Generated by Maestro Pipeline
This CLAUDE.md was generated by the Maestro autonomous pipeline to document
project commands and conventions. Feel free to edit and expand it.
GENEOF
  fi
  [ -f "CLAUDE.md" ] && echo "Generated temporary CLAUDE.md" || echo "Could not auto-detect project type for CLAUDE.md"
fi
```

Now read the CLAUDE.md (existing or generated):

```bash
cat CLAUDE.md 2>/dev/null || echo "No CLAUDE.md available"
```

**Note:** If CLAUDE.md was generated, commit it to the repo — it's a permanent
addition that helps all future pipeline runs and human developers. Include it
in the PR.

### Classify the task type

Determine: **feature**, **bug-fix**, **security-fix**, or **refactor**.

### Create pipeline branch from the default branch

**CRITICAL:** Always branch from the repo's default branch (master/main),
never from an existing pipeline branch. PRs will target `develop`.

```bash
# Unshallow so diffs work properly
git fetch --unshallow 2>/dev/null || true

# Detect default branch and ensure we're on it
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
git checkout "$DEFAULT_BRANCH"
git pull origin "$DEFAULT_BRANCH"

# Create a fresh pipeline branch — include issue number for clarity
git checkout -b "pipeline/issue-${ISSUE_NUM}-$(date +%Y%m%d-%H%M%S)"
```

### Write PIPELINE.md (fresh — never reuse from previous runs)

Write `PIPELINE.md`:
```markdown
# Pipeline Run

## Task
{task description + issue details}

## Type
{feature | bug-fix | security-fix | refactor}

## Status
IN_PROGRESS
```

```bash
git add PIPELINE.md
git commit -m "pipeline: start"
git push -u origin HEAD
```

---

## Phase 1 — Investigate

**Read the gstack investigate skill and follow its methodology:**

```bash
head -100 ~/.claude/skills/gstack/investigate/SKILL.md
```

Follow every step in that SKILL.md to investigate the issue. Apply the Iron Law:
no fixes without investigation. When done, append `## Investigation` to
PIPELINE.md with your findings (root cause, affected files, approach).

```bash
git add PIPELINE.md && git commit -m "pipeline: investigate" && git push
```

---

## Phase 2 — Think

**Read the gstack office-hours skill and follow its methodology:**

```bash
head -100 ~/.claude/skills/gstack/office-hours/SKILL.md
```

Follow the six forcing questions. Write a design document. Append `## Think`
to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: think" && git push
```

---

## Phase 3 — Plan

**Read the gstack plan-eng-review skill and follow its methodology:**

```bash
head -100 ~/.claude/skills/gstack/plan-eng-review/SKILL.md
```

Lock in architecture, data flow, edge cases, test plan. Append `## Plan`
to PIPELINE.md.

```bash
git add PIPELINE.md && git commit -m "pipeline: plan" && git push
```

---

## Phase 3.5 — Bootstrap Tests (if no test suite exists)

Before building, check if the project has tests. If not, create a test
foundation so the Review and QA phases have something to validate against.

```bash
# Check if any tests exist
TEST_FILES=$(find . -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "test_*" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -5)
echo "Existing test files: ${TEST_FILES:-NONE}"
```

If `TEST_FILES` is empty (no tests exist), bootstrap a test framework:

**For Node.js projects (package.json exists):**
- If Jest is not installed: add it to devDependencies
- Create a basic `jest.config.js` if missing
- Write smoke tests for the main modules: import each, check exports exist
- Write at least one integration test for the primary API/component

**For Go projects (go.mod exists):**
- Create `*_test.go` files for main packages with basic function tests

**For Python projects (requirements.txt exists):**
- Create `tests/` directory with `conftest.py` and basic test files
- Add `pytest` to requirements if missing

**For Android (build.gradle exists):**
- Create basic unit tests in `app/src/test/` for ViewModels and repositories

After bootstrapping, run the tests to verify they pass:

```bash
# Run the test command appropriate for the project type
npm test 2>&1 | tail -20 || ./gradlew test 2>&1 | tail -20 || go test ./... 2>&1 | tail -20 || pytest 2>&1 | tail -20 || echo "Tests bootstrapped but could not run"
```

Commit the test infrastructure:
```bash
git add -A && git commit -m "pipeline: bootstrap test suite" && git push
```

Append `## Test Bootstrap` to PIPELINE.md noting what was created.

If tests already exist, skip this phase entirely.

---

## Phase 4 — Build

Implement the changes.

1. Read PIPELINE.md for context (task, investigation, plan)
2. Make the minimal, correct changes needed
3. Follow existing code patterns
4. Write tests if the project has a test framework

Run tests using the command from CLAUDE.md:

```bash
# Read test command from CLAUDE.md, or auto-detect
if [ -f "package.json" ]; then
  npm test 2>&1 | tail -30
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  ./gradlew test 2>&1 | tail -30
elif [ -f "go.mod" ]; then
  go test ./... 2>&1 | tail -30
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  pytest 2>&1 | tail -30
elif [ -f "pubspec.yaml" ]; then
  flutter test 2>&1 | tail -30
else
  echo "No test runner detected"
fi
```

Commit:
```bash
git add -A && git commit -m "pipeline: implement changes" && git push
```

Append `## Build` to PIPELINE.md with files changed and test results.

---

## Phase 5 — Review

**Read the gstack review skill and follow its FULL methodology:**

```bash
head -100 ~/.claude/skills/gstack/review/SKILL.md
```

Follow every step — the checklist, the completeness checks, the regression
analysis, the auto-fix patterns. Review the diff:

```bash
git diff main..HEAD 2>/dev/null || git diff develop..HEAD 2>/dev/null || git diff master..HEAD
```

If you find issues: fix them, commit, re-review. Max 3 fix iterations.

Append `## Review` to PIPELINE.md with verdict and findings.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: review" && git push
```

---

## Phase 6 — Security

**Read the gstack cso skill and follow its FULL methodology:**

```bash
head -100 ~/.claude/skills/gstack/cso/SKILL.md
```

Follow the complete OWASP Top 10 + STRIDE audit. Apply the confidence gate
(8/10+), the false positive exclusions, the independent verification.
Each finding must have a concrete exploit scenario.

If critical vulnerabilities found: fix them, commit, re-audit.

Append `## Security` to PIPELINE.md with verdict.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: security" && git push
```

---

## Phase 7 — QA

**Read the gstack qa skill and follow its methodology:**

```bash
head -100 ~/.claude/skills/gstack/qa/SKILL.md
```

Run automated tests first (same detection as Phase 4).

If the browse binary exists, test visually:

```bash
B=~/.claude/skills/gstack/browse/dist/browse
[ -x "$B" ] && echo "Browse available" || echo "No browse binary — skip browser tests"
```

If bugs found: fix them, generate regression tests, re-verify.

Append `## QA` to PIPELINE.md with test results.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: qa" && git push
```

---

## Phase 8 — Ship

**Read the gstack ship skill and follow its methodology:**

```bash
head -100 ~/.claude/skills/gstack/ship/SKILL.md
```

### Create PR

Follow the ship workflow: sync main, final test run, create PR to develop.

```bash
PR_TITLE="$(sed -n '/^## Task/,/^## /p' PIPELINE.md | head -n -1 | tail -n +2 | head -1 | cut -c1-70)"
PR_BODY="$(cat PIPELINE.md)

---
*Created autonomously by the Maestro pipeline.*"

# PR targets develop — changes get reviewed there first.
# Once verified in develop, a separate develop → main PR handles promotion.
gh pr create \
  --base "develop" \
  --title "$PR_TITLE" \
  --body "$PR_BODY"
```

Update PIPELINE.md `## Status` to `COMPLETE`. Add `## Ship` with PR URL.

```bash
git add PIPELINE.md && git commit -m "pipeline: shipped" && git push
```

---

## Context Management

If at any point the conversation is getting long:
1. Summarize completed phases in PIPELINE.md
2. PIPELINE.md IS your memory — everything important is there
3. Continue with the next phase

## Iteration Guard

If review, security, or QA finds issues and you've already fixed 3 times:
- Update `## Status` to `NEEDS_HUMAN`
- Commit and push
- Stop: "Pipeline needs human review after 3 fix iterations"

## Final Output

```
COMPLETE: {PR URL}
Task: {brief description}
Phases: {list of phases completed}
```
