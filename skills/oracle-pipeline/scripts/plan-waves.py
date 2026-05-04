#!/usr/bin/env python3
"""Group stories into parallel-safe "waves" by module-disjointness.

Two stories are wave-compatible iff their STORY_AFFECTED_MODULES sets do
not intersect (token-wise, after lowercasing and stripping). Within a wave,
all stories can be implemented concurrently in worktree-isolated agents.

Reads:
  /tmp/oracle-work/stories-order.txt          (epic<TAB>story<TAB>title)
  /tmp/oracle-work/story-meta/N-M.sh          (STORY_AFFECTED_MODULES=...)

Writes:
  /tmp/oracle-work/waves.txt                  one line per wave, tab-separated
                                              records of  EPIC|STORY|TITLE|MODULES

Algorithm: greedy first-fit graph coloring.
  - Iterate stories in BMAD order.
  - For each story, place it in the first existing wave where no member's
    module set intersects this story's set; otherwise open a new wave.
  - Stable, deterministic, preserves epic ordering.
"""
from __future__ import annotations
import os
import re
import shlex
import sys
from pathlib import Path

WORK = Path(os.environ.get("ORACLE_WORK", "/tmp/oracle-work"))
ORDER = WORK / "stories-order.txt"
META_DIR = WORK / "story-meta"
OUT = WORK / "waves.txt"


def parse_modules(meta_file: Path) -> set[str]:
    if not meta_file.exists():
        return set()
    raw = meta_file.read_text()
    m = re.search(r"STORY_AFFECTED_MODULES=(.+?)\nSTORY_AC=", raw, re.S)
    if not m:
        return set()
    val = m.group(1).strip()
    # The metadata is shell-quoted with sh_quote(); parse with shlex.
    try:
        tokens = shlex.split(val)
    except ValueError:
        tokens = val.split()
    payload = " ".join(tokens) if tokens else ""
    parts = re.split(r"[,\s/]+", payload.lower())
    return {p.strip("`'\"") for p in parts if p.strip()}


def main() -> int:
    if not ORDER.exists():
        print(f"BLOCKED: {ORDER} missing — run 01-setup-workspace.sh first", file=sys.stderr)
        return 1

    waves: list[list[tuple[int, int, str, set[str]]]] = []

    for line in ORDER.read_text().splitlines():
        line = line.rstrip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        try:
            epic = int(parts[0])
            story = int(parts[1])
        except ValueError:
            continue
        title = parts[2]
        modules = parse_modules(META_DIR / f"{epic}-{story}.sh")

        placed = False
        for wave in waves:
            if all(modules.isdisjoint(m) for (_, _, _, m) in wave):
                wave.append((epic, story, title, modules))
                placed = True
                break
        if not placed:
            waves.append([(epic, story, title, modules)])

    with OUT.open("w") as fh:
        for wave in waves:
            records = [f"{e}|{s}|{t}|{','.join(sorted(m))}" for (e, s, t, m) in wave]
            fh.write("\t".join(records) + "\n")

    total_stories = sum(len(w) for w in waves)
    sequential_estimate = total_stories
    parallel_estimate = len(waves)
    speedup = (sequential_estimate / parallel_estimate) if parallel_estimate else 0.0
    print(
        f"Wrote {len(waves)} waves covering {total_stories} stories "
        f"(sequential={sequential_estimate}, parallel-waves={parallel_estimate}, "
        f"theoretical speedup={speedup:.2f}x)",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
