---
name: pipeline
description: |
  Autonomous dev pipeline — runs the full gstack sprint in one session.
  Auto-detects project stack, installs deps, generates temp CLAUDE.md if missing.
  Builds a persistent codebase map for large repos. Reads actual gstack SKILL.md files.
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

# Clone the CORRECT repo fresh
gh repo clone "$REPO" . 2>&1

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

**CRITICAL:** Always branch from the repo's default branch (master/main/develop),
never from an existing pipeline branch. Check which branch you're on.

```bash
# Detect default branch and ensure we're on it
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
git checkout "$DEFAULT_BRANCH"
git pull origin "$DEFAULT_BRANCH"

# Create a fresh pipeline branch — include issue number for clarity
git checkout -b "pipeline/issue-${ISSUE_NUM}-$(date +%Y%m%d-%H%M%S)"
```

---

## Phase 0.5 — Codebase Reconnaissance

**CRITICAL FOR LARGE REPOS.** Before doing ANY exploration, build or load a
codebase map. This prevents wasting context on blind directory traversals.

### Step 1: Check for existing codebase map

```bash
if [ -f ".pipeline/CODEBASE_MAP.md" ]; then
  echo "=== EXISTING CODEBASE MAP FOUND ==="
  cat .pipeline/CODEBASE_MAP.md
else
  echo "=== NO CODEBASE MAP — WILL GENERATE ==="
fi
```

If `.pipeline/CODEBASE_MAP.md` exists, read it and skip to Step 3.
If not, proceed to Step 2 to generate one.

### Step 2: Generate codebase map (first pipeline run only)

**DO NOT read individual files to build this map.** Use fast shell commands
to extract structure. This entire step should take < 30 seconds.

```bash
mkdir -p .pipeline

# --- Gather structure data with fast shell commands ---

# Top-level directory layout
echo "## Directory Structure (depth 2)" > /tmp/_map_dirs.txt
find . -maxdepth 2 -type d \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/.next/*' \
  -not -path '*/coverage/*' \
  -not -path '*/__pycache__/*' \
  | sort >> /tmp/_map_dirs.txt

# Source file counts by directory (identifies large vs small areas)
echo "## File Counts by Directory" > /tmp/_map_counts.txt
find . -type f -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
  -o -name '*.py' -o -name '*.go' -o -name '*.java' -o -name '*.kt' \
  -o -name '*.dart' -o -name '*.rb' -o -name '*.vue' -o -name '*.svelte' \
  2>/dev/null \
  | grep -v node_modules | grep -v '.git/' \
  | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -30 >> /tmp/_map_counts.txt

# Key config files (tells us about the architecture)
echo "## Key Config Files" > /tmp/_map_config.txt
for f in package.json tsconfig.json webpack.config.* vite.config.* \
  next.config.* craco.config.* .eslintrc* tailwind.config.* \
  build.gradle* settings.gradle* go.mod Cargo.toml pyproject.toml \
  pubspec.yaml Gemfile docker-compose.yml Dockerfile; do
  [ -f "$f" ] && echo "- $f" >> /tmp/_map_config.txt
done

# Route/page structure (React Router, Next.js pages, etc.)
echo "## Routes & Pages" > /tmp/_map_routes.txt
# React Router routes
grep -rn "path=" src/ --include='*.tsx' --include='*.ts' --include='*.jsx' --include='*.js' 2>/dev/null \
  | grep -i 'route\|path' | head -30 >> /tmp/_map_routes.txt 2>/dev/null
# Next.js pages
find ./pages ./app ./src/pages ./src/app -name '*.tsx' -o -name '*.ts' -o -name '*.jsx' -o -name '*.js' 2>/dev/null \
  | grep -v node_modules | sort >> /tmp/_map_routes.txt 2>/dev/null

# Component index (what components exist and where)
echo "## Components" > /tmp/_map_components.txt
find . -type f \( -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/dist/*' -not -path '*/build/*' \
  2>/dev/null | sort >> /tmp/_map_components.txt

# State management & API layer
echo "## State & API" > /tmp/_map_state.txt
grep -rl "createSlice\|createStore\|useReducer\|createContext\|zustand\|mobx\|vuex\|pinia" \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' . 2>/dev/null \
  | grep -v node_modules | head -20 >> /tmp/_map_state.txt
grep -rl "axios\|fetch(\|useSWR\|useQuery\|createApi\|httpClient" \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' . 2>/dev/null \
  | grep -v node_modules | head -20 >> /tmp/_map_state.txt

# Test infrastructure
echo "## Test Files" > /tmp/_map_tests.txt
find . -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.*' -o -name 'test_*' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null \
  | head -20 >> /tmp/_map_tests.txt

echo "Data gathered."
```

Now read ARCHITECTURE.md or README.md if they exist (these are short, high-value):

```bash
# Read architecture docs (if they exist — usually < 500 lines, very high value)
[ -f "ARCHITECTURE.md" ] && head -200 ARCHITECTURE.md
[ -f "README.md" ] && head -100 README.md
```

Now assemble the codebase map:

```bash
cat > .pipeline/CODEBASE_MAP.md << 'MAPEOF'
# Codebase Map
Generated by Maestro Pipeline. Updated incrementally on each run.
MAPEOF

# Append all gathered data
cat /tmp/_map_dirs.txt >> .pipeline/CODEBASE_MAP.md
echo "" >> .pipeline/CODEBASE_MAP.md
cat /tmp/_map_counts.txt >> .pipeline/CODEBASE_MAP.md
echo "" >> .pipeline/CODEBASE_MAP.md
cat /tmp/_map_config.txt >> .pipeline/CODEBASE_MAP.md
echo "" >> .pipeline/CODEBASE_MAP.md
cat /tmp/_map_routes.txt >> .pipeline/CODEBASE_MAP.md
echo "" >> .pipeline/CODEBASE_MAP.md
cat /tmp/_map_components.txt >> .pipeline/CODEBASE_MAP.md
echo "" >> .pipeline/CODEBASE_MAP.md
cat /tmp/_map_state.txt >> .pipeline/CODEBASE_MAP.md
echo "" >> .pipeline/CODEBASE_MAP.md
cat /tmp/_map_tests.txt >> .pipeline/CODEBASE_MAP.md

# Cleanup
rm -f /tmp/_map_*.txt

echo "=== CODEBASE MAP GENERATED ==="
wc -l .pipeline/CODEBASE_MAP.md
```

### Step 3: Focused issue analysis using the map

Now that you have the codebase map, use it to identify ONLY the files relevant
to the issue. **DO NOT explore the entire codebase.** Instead:

1. Read the issue title and body carefully
2. Identify keywords (component names, feature areas, error messages)
3. Use `grep -rn "keyword"` to find the exact files involved
4. Read ONLY those files — typically 3-10 files, not 50+

```bash
# Example: if the issue mentions "CommandPalette", find it precisely
# grep -rn "CommandPalette" src/ --include='*.tsx' --include='*.ts' -l
# Then read ONLY those files
```

**SMART EXPLORATION:** Use grep to find the right files first, then read them.
Start with the files directly named in the issue, then follow imports outward.
Prefer reading specific line ranges over full files when you only need part of it.
Read as many files as you need — but always grep-first to avoid wasting reads
on irrelevant files.

**USE SUB-AGENTS for parallel exploration.** When you need to understand multiple
areas of the codebase, use the `Agent` tool to spawn exploration sub-agents:

```
Use the Agent tool with subagent_type="Explore" to search for related files.
For example, if you need to find both the CommandPalette component AND the
UserDetailsModal component, spawn two Explore agents in parallel — one for
each component. This is faster and doesn't bloat your main context.
```

Write the issue-relevant file list to PIPELINE.md so later phases know
exactly which files to focus on.

Commit the codebase map (it persists for future runs):

```bash
git add .pipeline/CODEBASE_MAP.md
git commit -m "pipeline: add codebase map" 2>/dev/null || true
```

---

### Write PIPELINE.md (fresh — never reuse from previous runs)

Write `PIPELINE.md`:
```markdown
# Pipeline Run

## Task
{task description + issue details}

## Type
{feature | bug-fix | security-fix | refactor}

## Relevant Files
{list of files identified during reconnaissance — ONLY these files should be modified}

## Status
IN_PROGRESS
```

```bash
git add PIPELINE.md
git commit -m "pipeline: start"
git push -u origin HEAD
```

---

## Phase 1 — Investigate (bug-fix and security-fix only)

Skip for features and refactors.

**Read the gstack investigate skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/investigate/SKILL.md
```

**IMPORTANT:** Scope your investigation to the files listed in PIPELINE.md
`## Relevant Files`. Do NOT explore the entire codebase. If investigation
reveals additional relevant files, add them to the list and update PIPELINE.md.

Follow every step in that SKILL.md to investigate the issue. Apply the Iron Law:
no fixes without investigation. When done, append `## Investigation` to
PIPELINE.md with your findings (root cause, affected files, approach).

```bash
git add PIPELINE.md && git commit -m "pipeline: investigate" && git push
```

---

## Phase 2 — Think (features only)

Skip for bug-fix, security-fix, and refactor.

**Read the gstack office-hours skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/office-hours/SKILL.md
```

Follow the six forcing questions. Write a design document. Append `## Think`
to PIPELINE.md.

**IMPORTANT:** Base your design on the codebase map and relevant files identified
in Phase 0.5. Do not explore new directories unless the design requires it.

```bash
git add PIPELINE.md && git commit -m "pipeline: think" && git push
```

---

## Phase 3 — Plan (features and refactors only)

Skip for bug-fix and security-fix.

**Read the gstack plan-eng-review skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/plan-eng-review/SKILL.md
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

**SCOPE DISCIPLINE:** Only modify files listed in PIPELINE.md `## Relevant Files`.
If you discover you need to change additional files, add them to the list first.

1. Read PIPELINE.md for context (task, investigation, plan, relevant files)
2. Read ONLY the relevant files identified in Phase 0.5
3. Make the minimal, correct changes needed
4. Follow existing code patterns (check neighboring files for style)
5. Write tests if the project has a test framework

**For large repos:** Use the Agent tool with `subagent_type="Explore"` to
search for patterns, imports, or usage of functions you're modifying. This
keeps your main context clean while getting the information you need.

### Safe Editing Strategy (CRITICAL for large files)

The Edit tool can fail and loop when `old_string` isn't unique in a large file.
This causes the session to spiral and freeze. Follow these rules:

**Before editing ANY file, check its size:**

```bash
wc -l path/to/file.tsx
```

**Choose your editing approach based on file size:**

1. **Small files (< 200 lines):** Use the Edit tool normally. The `old_string`
   is likely unique.

2. **Medium files (200-500 lines):** Use the Edit tool but include MORE context
   in `old_string` — at least 5-10 lines of surrounding code to ensure uniqueness.
   If the Edit fails with "not unique", immediately switch to approach 3.

3. **Large files (500+ lines):** Do NOT use the Edit tool. Instead:
   - **Option A — Write tool:** Read the full file, make your changes in memory,
     then use the Write tool to write the entire modified file. This always works
     regardless of file size.
   - **Option B — New file extraction:** If you're adding a new component or
     section, create it as a NEW file and import it. This is often the cleanest
     approach for features.
   - **Option C — Targeted sed via Bash:** For surgical single-line changes,
     use sed with line numbers:
     ```bash
     # Find the exact line number first
     grep -n "the exact string" path/to/file.tsx
     # Then replace by line number
     sed -i '42s/old text/new text/' path/to/file.tsx
     ```

**NEVER retry a failed Edit more than once.** If the Edit tool errors with
"old_string is not unique" or similar, immediately switch to Write or sed.
Do not try to adjust the old_string — that path leads to infinite loops.

**When creating new components:** Always prefer creating a NEW file over
modifying an existing large file. For example, if adding a dashboard widget,
create `src/components/DashboardWidget.tsx` and import it, rather than adding
200 lines to an existing 800-line file.

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

### Update codebase map

After building, update the codebase map with any new discoveries about the
codebase that would help future pipeline runs:

```bash
# Append new learnings to the map
cat >> .pipeline/CODEBASE_MAP.md << UPDATEEOF

## Update ($(date +%Y-%m-%d)) — Issue #${ISSUE_NUM}
### Files Modified
$(git diff --name-only HEAD~1)
### Patterns Discovered
{Describe any architectural patterns, conventions, or gotchas you found}
UPDATEEOF

git add .pipeline/CODEBASE_MAP.md && git commit -m "pipeline: update codebase map" && git push
```

---

## Phase 4.5 — Design Review (UI changes only)

Skip if the changes are backend-only, config-only, or have no visual impact.
Run this phase if ANY `.tsx`, `.jsx`, `.css`, `.scss`, or `.module.css` files
were modified.

**Read the gstack design-review skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/design-review/SKILL.md
```

Focus on the diff — check spacing, alignment, hierarchy, color consistency,
and responsive behavior of the changed components. If the browse binary is
available, take screenshots to compare before/after.

If design issues found: fix them, commit. Max 2 fix iterations.

Append `## Design Review` to PIPELINE.md with findings.

```bash
git add -A && git commit -m "pipeline: design review fixes" && git push 2>/dev/null || true
git add -A PIPELINE.md && git commit -m "pipeline: design review" && git push
```

---

## Phase 5 — Review

**Read the gstack review skill and follow its FULL methodology:**

```bash
cat ~/.claude/skills/gstack/review/SKILL.md
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
cat ~/.claude/skills/gstack/cso/SKILL.md
```

Follow the complete OWASP Top 10 + STRIDE audit. Apply the confidence gate
(8/10+), the false positive exclusions, the independent verification.
Each finding must have a concrete exploit scenario.

**SCOPE:** Only audit files in the diff, not the entire codebase.

If critical vulnerabilities found: fix them, commit, re-audit.

Append `## Security` to PIPELINE.md with verdict.

```bash
git add -A PIPELINE.md && git commit -m "pipeline: security" && git push
```

---

## Phase 7 — QA

**Read the gstack qa skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/qa/SKILL.md
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
cat ~/.claude/skills/gstack/ship/SKILL.md
```

### Create PR

Follow the ship workflow: sync main, final test run, create PR with full
pipeline report.

```bash
BASE=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
gh pr create \
  --base "$BASE" \
  --title "$(sed -n '/^## Task/,/^## /p' PIPELINE.md | head -n -1 | tail -n +2 | head -1 | cut -c1-70)" \
  --body "$(cat PIPELINE.md)

---
*Created autonomously by the Maestro pipeline.*"
```

Update PIPELINE.md `## Status` to `COMPLETE`. Add `## Ship` with PR URL.

```bash
git add PIPELINE.md && git commit -m "pipeline: shipped" && git push
```

---

## Phase 9 — Document Release

**Read the gstack document-release skill and follow its methodology:**

```bash
cat ~/.claude/skills/gstack/document-release/SKILL.md
```

Update any project documentation that is now out of date because of the
changes shipped in this pipeline run. This includes:

- README.md — if new features, commands, or setup steps were added
- ARCHITECTURE.md — if structural changes were made
- CLAUDE.md — if new commands, conventions, or patterns were introduced
- Any other docs referenced in the codebase

Only update docs that are actually affected by the changes. Do not touch
docs that are still accurate.

Append `## Documentation` to PIPELINE.md listing what was updated.

```bash
git add -A && git commit -m "pipeline: update documentation" && git push
```

---

## Context Management

If at any point the conversation is getting long:
1. Summarize completed phases in PIPELINE.md
2. PIPELINE.md IS your memory — everything important is there
3. Continue with the next phase

## Exploration Best Practices

These practices help you stay efficient on large repos. They are guidelines,
not hard limits — read as many files as the task requires.

1. **Grep before read.** Before reading a file, grep for the specific function
   or component name to verify it's the right file. Avoids wasting context on
   irrelevant files.
2. **Read the codebase map first.** `.pipeline/CODEBASE_MAP.md` tells you where
   things are. Don't re-explore what's already mapped.
3. **Use sub-agents for broad exploration.** When you need to understand multiple
   areas of the codebase at once, spawn `Explore` sub-agents in parallel. Their
   context is separate — keeps your main session clean for the actual work.
4. **Read files partially when possible.** Use specific line ranges instead of
   full files when you only need to understand the interface or exports.
5. **Never blindly traverse directories.** Always use `grep -rn` or `find` with
   specific patterns rather than reading every file in a folder.

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
