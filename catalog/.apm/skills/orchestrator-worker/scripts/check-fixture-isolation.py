#!/usr/bin/env python3
"""Reject fixture dependency links that resolve outside the fixture root."""

import os
import sys
from pathlib import Path

PRUNED_DIRECTORY_NAMES = {
    ".cache",
    ".git",
    ".hg",
    ".svn",
    ".venv",
    "build",
    "coverage",
    "dist",
    "target",
    "venv",
}


def is_within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def check_link(path: Path, root: Path, issues: list[str]) -> bool:
    try:
        resolved = path.resolve(strict=False)
    except (OSError, RuntimeError) as error:
        issues.append(f"cannot resolve dependency link {path.relative_to(root)}: {error}")
        return False

    if not is_within(resolved, root):
        issues.append(f"dependency link escapes fixture root: {path.relative_to(root)} -> {resolved}")
        return False
    return True


def check_node_modules(path: Path, root: Path, issues: list[str]) -> None:
    if path.is_symlink() and not check_link(path, root, issues):
        return

    try:
        resolved_node_modules = path.resolve(strict=False)
        with os.scandir(resolved_node_modules) as entries:
            for entry in entries:
                child = Path(entry.path)
                if entry.name in {".pnpm", ".pnpm-store"}:
                    if child.is_symlink():
                        check_link(child, root, issues)
                    continue
                if entry.name.startswith("@") and (entry.is_dir(follow_symlinks=False) or entry.is_symlink()):
                    check_scoped_package_links(child, root, issues)
                    continue
                if entry.is_symlink():
                    check_link(child, root, issues)
                    continue
    except OSError as error:
        issues.append(f"cannot inspect dependency links in {path.relative_to(root)}: {error}")


def check_scoped_package_links(path: Path, root: Path, issues: list[str]) -> None:
    if path.is_symlink() and not check_link(path, root, issues):
        return

    try:
        with os.scandir(path.resolve(strict=False)) as entries:
            for entry in entries:
                if entry.is_symlink():
                    check_link(path / entry.name, root, issues)
    except OSError as error:
        issues.append(f"cannot inspect scoped dependencies in {path.relative_to(root)}: {error}")


def find_dependency_link_issues(root: Path) -> list[str]:
    issues: list[str] = []
    pending = [root]

    while pending:
        directory = pending.pop()
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    path = Path(entry.path)
                    if entry.name == "node_modules":
                        check_node_modules(path, root, issues)
                        continue
                    if entry.name in {".pnpm", ".pnpm-store"}:
                        if entry.is_symlink():
                            check_link(path, root, issues)
                        continue
                    if entry.name in PRUNED_DIRECTORY_NAMES:
                        continue
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            pending.append(path)
                    except OSError as error:
                        issues.append(f"cannot inspect fixture entry {path.relative_to(root)}: {error}")
        except OSError as error:
            issues.append(f"cannot scan fixture directory {directory.relative_to(root)}: {error}")

    return issues


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} FIXTURE_ROOT", file=sys.stderr)
        return 2

    try:
        root = Path(sys.argv[1]).resolve(strict=True)
    except (OSError, RuntimeError) as error:
        print(f"invalid fixture root: {error}", file=sys.stderr)
        return 2
    if not root.is_dir():
        print("fixture root must be a directory", file=sys.stderr)
        return 2

    issues = find_dependency_link_issues(root)
    if issues:
        print("\n".join(issues), file=sys.stderr)
        return 1

    print("fixture dependency links stay inside the fixture root")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
