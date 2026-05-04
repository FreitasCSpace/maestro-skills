#!/usr/bin/env python3
"""Parse BMAD stories-output.md into per-story shell metadata files.

Writes:
  stories-order.txt        — one line per story: EPIC_NUM<tab>STORY_NUM<tab>TITLE
  story-meta/N-M.sh        — STORY_AFFECTED_MODULES and STORY_AC for story N.M

Usage:
  extract-stories.py <stories-output.md> <meta_dir> <order_file>
"""
import sys, re, os


def sh_quote(s: str) -> str:
    return "'" + s.replace("'", "'\\''") + "'"


def main() -> int:
    raw_file, meta_dir, order_file = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(meta_dir, exist_ok=True)

    with open(raw_file) as f:
        lines = f.readlines()

    epic_num = 0
    story_num = 0
    story_title = ""
    in_field = None
    buf: list[str] = []
    modules = ""
    ac_parts: list[str] = []
    order: list[str] = []

    def flush_field() -> None:
        nonlocal modules, ac_parts
        if in_field == "modules":
            modules = " ".join(filter(None, buf))
        elif in_field == "ac":
            ac_parts = list(filter(None, buf))

    def save_story() -> None:
        if not story_num:
            return
        fname = os.path.join(meta_dir, f"{epic_num}-{story_num}.sh")
        with open(fname, "w") as f:
            f.write(f"STORY_AFFECTED_MODULES={sh_quote(modules)}\n")
            f.write(f"STORY_AC={sh_quote(' | '.join(ac_parts))}\n")
        order.append(f"{epic_num}\t{story_num}\t{story_title}")

    for raw in lines:
        line = raw.rstrip()

        m = re.match(r'^##\s+(?:Epic\s+)?(\d+)[\s:.—–-]', line)
        if m:
            flush_field(); save_story()
            story_num = 0; story_title = ""; modules = ""; ac_parts = []
            in_field = None; buf = []
            epic_num = int(m.group(1)); continue

        m = re.match(r'^###\s+(?:Story\s+)?(?:\d+\.)?(\d+)[\s:.—–-]+(.+)', line)
        if m:
            flush_field(); save_story()
            in_field = None; buf = []; modules = ""; ac_parts = []
            story_num = int(m.group(1)); story_title = m.group(2).strip(); continue

        if not story_num:
            continue

        m = re.match(r'^\*\*(?:affected_modules|Affected Modules)\*\*[:\s]*(.*)', line)
        if m:
            flush_field(); in_field = "modules"; buf = []
            val = m.group(1).strip().lstrip(':').strip()
            if val: buf.append(val); continue

        if re.match(r'^\*\*(?:acceptance_criteria|Acceptance Criteria)\*\*', line):
            flush_field(); in_field = "ac"; buf = []; continue

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
    return 0


if __name__ == "__main__":
    sys.exit(main())
