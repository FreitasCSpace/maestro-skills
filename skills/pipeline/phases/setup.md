# Phase 0 — Setup

## Read task input

```bash
echo "$CLAUDEHUB_INPUT_KWARGS"
```

Extract the `task` field. This is YOUR task for THIS run. It has NOT been done yet.

## Authenticate GitHub

```bash
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
gh auth status
```

## Clone the target repo

**CRITICAL:** You MUST work on the repo referenced in the task, NOT whatever
repo is already in the working directory.

Extract the repo owner/name from the task. If the task contains a GitHub issue
URL like `https://github.com/carespace-ai/carespace-admin/issues/146`, the
repo is `carespace-ai/carespace-admin`.

```bash
TASK=$(echo "$CLAUDEHUB_INPUT_KWARGS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task',''))")
REPO=$(echo "$TASK" | grep -oP 'github\.com/\K[^/]+/[^/]+' | head -1)
echo "Target repo: $REPO"
```

```bash
rm -rf /tmp/pipeline-work 2>/dev/null
mkdir -p /tmp/pipeline-work
cd /tmp/pipeline-work

# Shallow clone — large repos fail full clone
gh repo clone "$REPO" . -- --depth=50 2>&1

rm -f PIPELINE.md 2>/dev/null
```

**IMPORTANT:** You MUST work in `/tmp/pipeline-work` for the entire run.

## Fetch issue details and screenshots

```bash
ISSUE_NUM=$(echo "$TASK" | grep -oP 'issues/\K\d+')
ISSUE_JSON=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body,labels,state)
echo "$ISSUE_JSON"
```

Download and optimize screenshots for visual analysis:

```bash
mkdir -p /tmp/pipeline-screenshots
ISSUE_BODY=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('body',''))")
IMG_URLS=$(echo "$ISSUE_BODY" | grep -oP 'https://[^\s\)\"]+\.(png|jpg|jpeg|gif|webp)' | head -5)
COUNT=0
for url in $IMG_URLS; do
  COUNT=$((COUNT + 1))
  ORIG="/tmp/pipeline-screenshots/orig-${COUNT}.png"
  FINAL="/tmp/pipeline-screenshots/issue-${COUNT}.png"
  curl -sL --max-time 15 "$url" -o "$ORIG" 2>/dev/null
  if [ -f "$ORIG" ] && [ -s "$ORIG" ]; then
    python3 -c "
from PIL import Image
img = Image.open('$ORIG')
if img.width > 800:
    ratio = 800 / img.width
    img = img.resize((800, int(img.height * ratio)), Image.LANCZOS)
img.save('$FINAL', 'PNG', optimize=True)
" 2>/dev/null && rm -f "$ORIG" || mv "$ORIG" "$FINAL"
    SIZE=$(stat -c%s "$FINAL" 2>/dev/null || echo 0)
    echo "Screenshot ready: issue-${COUNT}.png (${SIZE} bytes)"
  else
    rm -f "$ORIG"
  fi
done
[ "$COUNT" -eq 0 ] && echo "No screenshots in issue body"
```

If screenshots were downloaded, view them with the Read tool:
```
Read tool → file_path: /tmp/pipeline-screenshots/issue-1.png
```

## Configure git

```bash
git config user.email "pipeline@carespace.ai"
git config user.name "CareSpace Pipeline"
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git"
```

## Auto-detect and install dependencies

```bash
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

## Read or generate CLAUDE.md

Read `CLAUDE.md` if it exists. If not, auto-generate one based on the project type.

```bash
cat CLAUDE.md 2>/dev/null || echo "No CLAUDE.md — will auto-generate if needed"
```

If CLAUDE.md doesn't exist, generate it from package.json/build files (same pattern
as before — detect test/build/lint/start commands and write them).

## Classify task type

Determine: **feature**, **bug-fix**, **security-fix**, or **refactor**.

## Create pipeline branch

```bash
git fetch --unshallow 2>/dev/null || true
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | sed 's/.*: //')
git checkout "$DEFAULT_BRANCH"
git pull origin "$DEFAULT_BRANCH"
git checkout -b "pipeline/issue-${ISSUE_NUM}-$(date +%Y%m%d-%H%M%S)"
```

## Write PIPELINE.md and push

```markdown
# Pipeline Run

## Task
{task description + issue details}

## Type
{feature | bug-fix | security-fix | refactor}

## Relevant Files
{to be filled during reconnaissance}

## Status
IN_PROGRESS
```

```bash
git add PIPELINE.md
git commit -m "pipeline: start"
git push -u origin HEAD
```
