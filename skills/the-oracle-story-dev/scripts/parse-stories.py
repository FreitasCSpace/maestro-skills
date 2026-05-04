#!/usr/bin/env python3
"""Parse stories-output.md from the-oracle-backlog into structured JSON.

The backlog uses a monolithic markdown file per feature with this shape:

    ---
    repos_affected: [carespace-admin, ...]
    feature: ...
    ---
    # <Feature> — Epic Breakdown
    ## Epic List
    ### Epic 1: ...
    #### Story 1.1: <title>
    **User outcome:** ...
    **Acceptance Criteria:**
    - AC...
    **FRs covered:** FR-001, FR-002

This script extracts a single story (or the next Ready story) and emits JSON.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml  # type: ignore


STORY_HEADER_RE = re.compile(r"^#{3,4}\s+Story\s+(\d+\.\d+)\s*[:\-—]\s*(.+?)\s*$", re.M)
EPIC_HEADER_RE = re.compile(r"^#{2,3}\s+Epic\s+(\d+)\s*[:\-—]\s*(.+?)\s*$", re.M)
FR_RE = re.compile(r"FR-\d+", re.I)


def split_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---"):
        return {}, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    try:
        return yaml.safe_load(parts[1]) or {}, parts[2]
    except yaml.YAMLError:
        return {}, text


def extract_stories(body: str) -> list[dict]:
    matches = list(STORY_HEADER_RE.finditer(body))
    epics = list(EPIC_HEADER_RE.finditer(body))

    stories: list[dict] = []
    for idx, m in enumerate(matches):
        start = m.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(body)
        block = body[start:end]

        epic_title = ""
        for em in epics:
            if em.start() < start:
                epic_title = em.group(2).strip()
            else:
                break

        ac = parse_section(block, ["acceptance criteria", "ac"])
        outcome = parse_inline(block, ["user outcome", "outcome"]) or parse_user_story(block)
        frs = sorted(set(FR_RE.findall(block)))

        stories.append(
            {
                "id": m.group(1),
                "story_title": m.group(2).strip(),
                "epic_title": epic_title,
                "user_outcome": outcome,
                "acceptance_criteria": ac,
                "frs_covered": frs,
                "raw_markdown": block.strip(),
            }
        )
    return stories


def parse_section(block: str, names: list[str]) -> list[str]:
    """Capture content under a `**Header:**` until the next markdown heading.

    Handles both bullet lists and paragraph-form content (e.g. Gherkin
    Given/When/Then groups separated by blank lines). Returns one entry
    per bullet OR per paragraph.
    """
    lines = block.splitlines()
    raw: list[str] = []
    capturing = False
    for line in lines:
        stripped = line.strip()
        low = stripped.lower().lstrip("*_# ").rstrip("*_: ").strip()
        if not capturing and any(low == n for n in names):
            capturing = True
            continue
        if capturing:
            if stripped.startswith(("####", "###", "##", "#")):
                break
            if re.match(r"^\*\*[^*]+\*\*\s*[:.]?\s*$", stripped) and \
               not re.match(r"^\*\*(Given|When|Then|And|But)\b", stripped, re.I):
                break
            raw.append(line)

    text = "\n".join(raw).strip()
    if not text:
        return []

    bullet_lines = [ln for ln in text.splitlines() if re.match(r"^\s*[-*+]\s+|^\s*\d+\.\s", ln)]
    if bullet_lines and len(bullet_lines) >= len([ln for ln in text.splitlines() if ln.strip()]) * 0.6:
        return [re.sub(r"^\s*[-*+]\s+|^\s*\d+\.\s+", "", ln).strip()
                for ln in bullet_lines if ln.strip()]

    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    return paragraphs


def parse_inline(block: str, names: list[str]) -> str:
    for line in block.splitlines():
        m = re.match(r"^\s*\*?\*?(?P<key>[^:*]+)\*?\*?\s*:\s*(?P<val>.+?)\s*$", line)
        if m and m.group("key").strip().lower() in names:
            return m.group("val").strip()
    return ""


def parse_user_story(block: str) -> str:
    """Extract the 'As a X, I want Y, So that Z' preamble as a single line."""
    m = re.search(
        r"As\s+(?:a|an)\s+\*?\*?(?P<role>[^,*\n]+)\*?\*?,?\s*\n?"
        r"\s*I\s+want\s+\*?\*?(?P<want>[^*\n]+(?:\n[^*\n]+)*?)\*?\*?,?\s*\n?"
        r"\s*So\s+that\s+\*?\*?(?P<so>[^*\n]+(?:\n[^*\n]+)*?)\*?\*?\.?",
        block,
        re.I,
    )
    if not m:
        return ""
    role = m.group("role").strip()
    want = re.sub(r"\s+", " ", m.group("want")).strip().rstrip(",.")
    so = re.sub(r"\s+", " ", m.group("so")).strip().rstrip(",.")
    return f"As a {role}, I want {want}, so that {so}."


def find_stories_file(backlog: Path, feature: str) -> Path:
    candidate = backlog / "bmad-context" / feature / "stories-output.md"
    if not candidate.exists():
        sys.exit(f"ERROR: {candidate} not found")
    return candidate


def pick_next_ready(stories: list[dict], manifest_path: Path | None) -> dict:
    if manifest_path and manifest_path.exists():
        with manifest_path.open() as f:
            manifest = yaml.safe_load(f) or {}
        statuses = {s["id"]: s.get("status", "Ready") for s in manifest.get("stories", [])}
    else:
        statuses = {}
    ready = [s for s in stories if statuses.get(s["id"], "Ready") == "Ready"]
    if not ready:
        sys.exit("ERROR: no Ready stories in manifest")
    return sorted(ready, key=lambda s: tuple(int(x) for x in s["id"].split(".")))[0]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--backlog", required=True)
    p.add_argument("--feature", required=True)
    p.add_argument("--story", default="next", help="Epic.Story id or 'next'")
    p.add_argument("--manifest", default=None, help="Sprint manifest YAML (used for 'next')")
    p.add_argument("--out", default="/tmp/story.json")
    p.add_argument("--list", action="store_true", help="List all stories and exit")
    args = p.parse_args()

    backlog = Path(args.backlog)
    stories_file = find_stories_file(backlog, args.feature)
    text = stories_file.read_text()
    fm, body = split_frontmatter(text)
    stories = extract_stories(body)

    if args.list:
        for s in stories:
            print(f"{s['id']:<6} {s['story_title']}  (FRs: {','.join(s['frs_covered'])})")
        return

    if args.story == "next":
        story = pick_next_ready(stories, Path(args.manifest) if args.manifest else None)
    else:
        story = next((s for s in stories if s["id"] == args.story), None)
        if story is None:
            sys.exit(f"ERROR: story {args.story} not found in {stories_file}")

    feature_dir = stories_file.parent
    raw_repos = fm.get("repos_affected", [])
    story["repos_affected"] = [re.sub(r"\s*\(.*\)\s*$", "", r).strip() for r in raw_repos]
    story["repos_affected_raw"] = raw_repos
    story["feature"] = fm.get("feature", args.feature)
    story["linked_docs"] = {
        "prd": str(feature_dir / "prd.md"),
        "architecture": str(feature_dir / "architecture.md"),
        "front_end_spec": str(feature_dir / "front-end-spec.md"),
        "feature_intent": str(feature_dir / "feature-intent.json"),
        "brief": str(feature_dir / "brief.md"),
        "po_validation": str(feature_dir / "po-validation.md"),
    }

    Path(args.out).write_text(json.dumps(story, indent=2))
    print(json.dumps(story, indent=2))


if __name__ == "__main__":
    main()
