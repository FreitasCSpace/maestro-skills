# Phase 01 — Workspace, BMAD Context, Stories Index

## Step 1.0 — Workspace

```bash
rm -rf /tmp/oracle-work 2>/dev/null
mkdir -p /tmp/oracle-work/workspace /tmp/oracle-work/stories
cd /tmp/oracle-work
```

## Step 1.1 — Clone backlog main, then fetch context files

Always clone main. If the bmad-context dir isn't on main, fetch it from the
context branch. This handles both cases (context on main or on a separate branch).

```bash
gh repo clone "$TARGET_ORG/the-oracle-backlog" backlog -- --depth=1
cd backlog

CTX_DIR="bmad-context/$PROJECT_SLUG"

# If context dir not on main, try to fetch it from the context branch
if [ ! -d "$CTX_DIR" ]; then
  CONTEXT_BRANCH="bmad/${PROJECT_SLUG}-context"
  git fetch origin "$CONTEXT_BRANCH" 2>/dev/null && \
    git checkout "origin/$CONTEXT_BRANCH" -- "$CTX_DIR" 2>/dev/null || {
    cd /tmp/oracle-work
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "BMAD context not found on main or on branch \`$CONTEXT_BRANCH\` — aborting"
    gh issue edit "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --remove-label oracle:implementing --add-label oracle:blocked-pipeline-failed
    exit 1
  }
  echo "Context fetched from $CONTEXT_BRANCH"
else
  echo "Context found on main"
fi

cd /tmp/oracle-work
CTX_DIR="backlog/bmad-context/$PROJECT_SLUG"

for f in feature-intent.json stories-output.md; do
  [ -f "$CTX_DIR/$f" ] || {
    gh issue comment "$ANCHOR" --repo "$TARGET_ORG/the-oracle-backlog" \
      --body "Missing required BMAD file: \`$f\`"
    exit 1
  }
done
```

## Step 1.2 — Extract involved repos (bash only, no Read tool)

```bash
INVOLVED_REPOS=($(jq -r '.involved_repos[].full_name | split("/")[1]' \
  "$CTX_DIR/feature-intent.json"))
echo "Involved repos: ${INVOLVED_REPOS[*]}"
[ ${#INVOLVED_REPOS[@]} -gt 0 ] || { echo "BLOCKED: no involved_repos in feature-intent.json"; exit 1; }
```

## Step 1.3 — Extract story metadata via bash (no Read tool)

```bash
STORIES_RAW="$CTX_DIR/stories-output.md"
STORIES_IDX="/tmp/oracle-work/stories-index.md"

mkdir -p /tmp/oracle-work/story-meta

# Compact index for debugging only
awk '
  /^## (Story|Epic)/ { print; next }
  /^### Story/       { print; next }
  /^\*\*(Story ID|title|affected_modules|new_files_needed|acceptance_criteria|dev_notes)\*\*/ { print; next }
  /^- /              { print; next }
' "$STORIES_RAW" > "$STORIES_IDX"

# Write the extraction script
cat > /tmp/oracle-work/extract-stories.py << 'PYEOF'
#!/usr/bin/env python3
"""Parse BMAD stories-output.md into per-story shell metadata files.

Writes:
  stories-order.txt        — one line per story: EPIC_NUM<tab>STORY_NUM<tab>TITLE
  story-meta/N-M.sh        — STORY_AFFECTED_MODULES and STORY_AC for story N.M
"""
import sys, re, os

def sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

raw_file, meta_dir, order_file = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(meta_dir, exist_ok=True)

lines = open(raw_file).readlines()

epic_num = 0; story_num = 0; story_title = ""
in_field = None; buf = []; modules = ""; ac_parts = []
order = []

def flush_field():
    global modules, ac_parts
    if in_field == "modules":
        modules = " ".join(filter(None, buf))
    elif in_field == "ac":
        ac_parts = list(filter(None, buf))

def save_story():
    if not story_num:
        return
    fname = os.path.join(meta_dir, f"{epic_num}-{story_num}.sh")
    with open(fname, "w") as f:
        f.write(f"STORY_AFFECTED_MODULES={sh_quote(modules)}\n")
        f.write(f"STORY_AC={sh_quote(' | '.join(ac_parts))}\n")
    order.append(f"{epic_num}\t{story_num}\t{story_title}")

for raw in lines:
    line = raw.rstrip()

    # Epic heading: ## Epic N  or  ## N.
    m = re.match(r'^##\s+(?:Epic\s+)?(\d+)[\s:.—–-]', line)
    if m:
        flush_field(); save_story()
        story_num = 0; story_title = ""; modules = ""; ac_parts = []
        in_field = None; buf = []
        epic_num = int(m.group(1)); continue

    # Story heading: ### Story N.M  or  ### N.M
    m = re.match(r'^###\s+(?:Story\s+)?(?:\d+\.)?(\d+)[\s:.—–-]+(.+)', line)
    if m:
        flush_field(); save_story()
        in_field = None; buf = []; modules = ""; ac_parts = []
        story_num = int(m.group(1)); story_title = m.group(2).strip(); continue

    if not story_num:
        continue

    # affected_modules field
    m = re.match(r'^\*\*(?:affected_modules|Affected Modules)\*\*[:\s]*(.*)', line)
    if m:
        flush_field(); in_field = "modules"; buf = []
        val = m.group(1).strip().lstrip(':').strip()
        if val: buf.append(val); continue

    # acceptance_criteria field
    if re.match(r'^\*\*(?:acceptance_criteria|Acceptance Criteria)\*\*', line):
        flush_field(); in_field = "ac"; buf = []; continue

    # Any other bold field or blank line ends collection
    if re.match(r'^\*\*', line) or not line.strip():
        flush_field(); in_field = None; buf = []; continue

    if in_field == "modules":
        val = re.sub(r'^[-*]\s*', '', line).strip()
        if val: buf.append(val)
    elif in_field == "ac":
        val = re.sub(r'^[-*]\s*(?:\[[ xX]?\]\s*)?', '', line).strip()
        if val: buf.append(val)

flush_field(); save_story()

with open(order_file, "w") as f:
    f.write("\n".join(order) + "\n")

print(f"Extracted {len(order)} stories", flush=True)
PYEOF

python3 /tmp/oracle-work/extract-stories.py \
  "$STORIES_RAW" \
  "/tmp/oracle-work/story-meta" \
  "/tmp/oracle-work/stories-order.txt"

TOTAL_STORIES=$(grep -c . /tmp/oracle-work/stories-order.txt 2>/dev/null || echo 0)
echo "Extracted $TOTAL_STORIES stories — sample: $(head -3 /tmp/oracle-work/stories-order.txt)"
[ "$TOTAL_STORIES" -gt 0 ] || { echo "BLOCKED: no stories found in stories-output.md"; exit 1; }
```

---

**Next:** Read `shards/phase-02-repos.md`
