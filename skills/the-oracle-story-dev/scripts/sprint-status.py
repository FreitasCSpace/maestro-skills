#!/usr/bin/env python3
"""Manage the local sprint manifest for a backlog feature.

The backlog repo has no sprint tracker. This skill owns one locally,
keyed by feature slug. Statuses: Ready | InProgress | Review | Done | Blocked.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml  # type: ignore


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    return yaml.safe_load(path.read_text()) or {}


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False))


def cmd_init(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest)
    existing = load(manifest_path)

    parse_script = Path(__file__).parent / "parse-stories.py"
    out = subprocess.check_output(
        [sys.executable, str(parse_script), "--backlog", args.backlog,
         "--feature", args.feature, "--list"],
        text=True,
    )
    parsed_ids = []
    for line in out.splitlines():
        if not line.strip():
            continue
        sid = line.split()[0]
        title = line.split(maxsplit=1)[1] if len(line.split(maxsplit=1)) > 1 else ""
        parsed_ids.append((sid, title.split("  (FRs:")[0].strip()))

    by_id = {s["id"]: s for s in existing.get("stories", [])}
    stories = []
    for sid, title in parsed_ids:
        prev = by_id.get(sid, {})
        stories.append({
            "id": sid,
            "title": title,
            "status": prev.get("status", "Ready"),
            "branch": prev.get("branch"),
            "pr_urls": prev.get("pr_urls", []),
            "note": prev.get("note"),
            "updated_at": prev.get("updated_at"),
        })

    data = {
        "feature": args.feature,
        "backlog": args.backlog,
        "created_at": existing.get("created_at", datetime.now(timezone.utc).isoformat()),
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "stories": stories,
    }
    save(manifest_path, data)
    print(f"Manifest written: {manifest_path} ({len(stories)} stories)")


def cmd_set(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest)
    data = load(manifest_path)
    if not data:
        sys.exit(f"ERROR: manifest {manifest_path} not initialized")

    found = False
    for story in data.get("stories", []):
        if story["id"] == args.story:
            if args.status:
                story["status"] = args.status
            if args.branch:
                story["branch"] = args.branch
            if args.pr_urls:
                story["pr_urls"] = [u.strip() for u in args.pr_urls.split(",") if u.strip()]
            if args.note:
                story["note"] = args.note
            story["updated_at"] = datetime.now(timezone.utc).isoformat()
            found = True
            break
    if not found:
        sys.exit(f"ERROR: story {args.story} not in manifest")

    data["updated_at"] = datetime.now(timezone.utc).isoformat()
    save(manifest_path, data)
    print(f"Updated {args.story} in {manifest_path}")


def cmd_show(args: argparse.Namespace) -> None:
    data = load(Path(args.manifest))
    if not data:
        sys.exit(f"ERROR: manifest {args.manifest} not initialized")
    if args.json:
        print(json.dumps(data, indent=2, default=str))
        return
    print(f"\nSprint: {data['feature']}\n")
    print(f"{'ID':<6} {'STATUS':<11} {'TITLE':<60} PR(s)")
    print("-" * 100)
    by_status = {"InProgress": 0, "Review": 1, "Blocked": 2, "Ready": 3, "Done": 4}
    for s in sorted(data["stories"], key=lambda s: (by_status.get(s["status"], 9),
                                                     tuple(int(x) for x in s["id"].split(".")))):
        prs = ", ".join(s.get("pr_urls") or [])
        print(f"{s['id']:<6} {s['status']:<11} {s['title'][:58]:<60} {prs}")


def main() -> None:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("init")
    pi.add_argument("--manifest", required=True)
    pi.add_argument("--backlog", required=True)
    pi.add_argument("--feature", required=True)
    pi.set_defaults(func=cmd_init)

    ps = sub.add_parser("set")
    ps.add_argument("--manifest", required=True)
    ps.add_argument("--story", required=True)
    ps.add_argument("--status", choices=["Ready", "InProgress", "Review", "Done", "Blocked"])
    ps.add_argument("--branch")
    ps.add_argument("--pr-urls")
    ps.add_argument("--note")
    ps.set_defaults(func=cmd_set)

    psh = sub.add_parser("show")
    psh.add_argument("--manifest", required=True)
    psh.add_argument("--json", action="store_true")
    psh.set_defaults(func=cmd_show)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
