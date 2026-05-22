#!/usr/bin/env python3
"""Inspect personal skill source candidates for CAAD marketplace deployment."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


DEFAULT_ROOTS = [
    Path("~/.apm/catalog/skills").expanduser(),
    Path("~/.apm/private-skills/.apm/skills").expanduser(),
    Path("~/.agents/skills").expanduser(),
]


def normalize_skill_name(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.strip().lower())
    return normalized.strip("-")


def read_frontmatter(skill_file: Path) -> dict[str, str]:
    text = skill_file.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}

    end = text.find("\n---", 4)
    if end == -1:
        return {}

    metadata: dict[str, str] = {}
    current_key = ""
    multiline: list[str] = []

    def flush_multiline() -> None:
        nonlocal current_key, multiline
        if current_key:
            metadata[current_key] = " ".join(part.strip() for part in multiline).strip()
        current_key = ""
        multiline = []

    for line in text[4:end].splitlines():
        if current_key and line.startswith((" ", "\t")):
            multiline.append(line)
            continue
        if line.startswith((" ", "\t")):
            continue

        flush_multiline()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        normalized_value = value.strip().strip('"')
        if normalized_value in {"|", ">"}:
            current_key = key.strip()
            multiline = []
        elif normalized_value:
            metadata[key.strip()] = normalized_value
        else:
            continue

    flush_multiline()
    return metadata


def inspect_candidate(path: Path) -> dict[str, object]:
    skill_file = path / "SKILL.md"
    result: dict[str, object] = {
        "path": str(path),
        "exists": path.exists(),
        "skill_file": str(skill_file),
        "has_skill_file": skill_file.is_file(),
    }
    if skill_file.is_file():
        result["frontmatter"] = read_frontmatter(skill_file)
        result["resources"] = [
            name
            for name in ("agents", "scripts", "references", "assets")
            if (path / name).exists()
        ]
        result["external_symlinks"] = [
            str(item)
            for item in path.rglob("*")
            if item.is_symlink() and not item.resolve().is_relative_to(path.resolve())
        ]
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("skill", help="Skill name or explicit skill directory path")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    args = parser.parse_args()

    raw = Path(args.skill).expanduser()
    candidates = [raw] if raw.exists() else [root / normalize_skill_name(args.skill) for root in DEFAULT_ROOTS]
    inspected = [inspect_candidate(candidate) for candidate in candidates]

    if args.json:
        print(json.dumps(inspected, ensure_ascii=False, indent=2))
    else:
        for candidate in inspected:
            status = "OK" if candidate["has_skill_file"] else "missing"
            print(f"{status}: {candidate['path']}")
            frontmatter = candidate.get("frontmatter")
            if isinstance(frontmatter, dict) and frontmatter:
                print(f"  name: {frontmatter.get('name', '')}")
                print(f"  description: {frontmatter.get('description', '')}")
            resources = candidate.get("resources")
            if resources:
                print(f"  resources: {', '.join(resources)}")

    return 0 if any(candidate["has_skill_file"] for candidate in inspected) else 1


if __name__ == "__main__":
    raise SystemExit(main())
