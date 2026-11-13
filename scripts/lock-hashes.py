#!/usr/bin/env python3
"""Prints "<sha256>  <path>" for every deployed_file_hashes record of an apm.lock.yaml, sorted.

With "pristine <lock> <home> <root>...", prints "<root>/<entry><TAB><digest>" instead for each top-level entry of
<home>/<root> that holds exactly the files and sha256 the lock records for it (digest: sha256 of those record lines).

Only the top-level dependencies' deployed_file_hashes mappings are read, as YAML structure. Anything unexpected exits
non-zero (nothing is printed), so a caller that approves from this output approves nothing from a lock it cannot trust.
Needs PyYAML; run it with the interpreter apm itself runs on.
"""

import hashlib
import os
import re
import stat
import sys

import yaml

HASH = re.compile(r"sha256:([0-9a-f]{64})")
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


class StrictLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        keys = [self.construct_object(key, deep=True) for key, _ in node.value]
        if len(set(map(repr, keys))) != len(keys):
            raise ValueError(f"duplicate key in the mapping at line {node.start_mark.line + 1}")
        return super().construct_mapping(node, deep)


def canonical(path):
    """A HOME-relative path as one spelling only: callers select records by string prefix."""
    try:
        path.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return (
        not CONTROL.search(path)
        and "\\" not in path
        and all(segment not in ("", ".", "..") for segment in path.split("/"))
    )


def fail(message):
    raise ValueError(message)


def records(lock):
    if not isinstance(lock, dict):
        fail("the top level is not a mapping")
    dependencies = lock.get("dependencies", [])
    if not isinstance(dependencies, list):
        fail("dependencies is not a list")
    found = {}
    for dependency in dependencies:
        if not isinstance(dependency, dict):
            fail("a dependency is not a mapping")
        if "deployed_file_hashes" not in dependency:
            continue
        hashes = dependency["deployed_file_hashes"]
        if not isinstance(hashes, dict):
            fail("deployed_file_hashes is not a mapping")
        for path, value in hashes.items():
            if not isinstance(path, str) or not canonical(path):
                fail(f"unusable path: {path!r}")
            match = HASH.fullmatch(value) if isinstance(value, str) else None
            if match is None:
                fail(f"{path}: the value is not sha256:<64 lowercase hex>")
            if found.setdefault(path, match.group(1)) != match.group(1):
                fail(f"{path} is recorded with different hashes")
    return found


def load_records(path):
    with open(path, encoding="utf-8") as handle:
        return records(yaml.load(handle, Loader=StrictLoader))


def deployed(path):
    return "__pycache__" not in path.split("/") and path.rsplit("/", 1)[-1] != ".apm-pin"


def entry_files(path):
    """{path relative to the entry's parent: absolute path} of the regular files of an entry that apm records (outside
    __pycache__, not .apm-pin); None when anything in it is neither a regular file nor a directory, links included."""
    pending = [(os.path.basename(path), path, False)]
    files = {}
    while pending:
        relative, current, in_cache = pending.pop()
        mode = os.lstat(current).st_mode
        if stat.S_ISREG(mode):
            if not in_cache and os.path.basename(current) != ".apm-pin":
                files[relative] = current
        elif stat.S_ISDIR(mode):
            in_cache = in_cache or (current != path and os.path.basename(current) == "__pycache__")
            with os.scandir(current) as children:
                pending.extend((f"{relative}/{child.name}", child.path, in_cache) for child in children)
        else:
            return None
    return files


def file_digest(path):
    digest = hashlib.sha256()
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def pristine(lock, home, roots):
    found = load_records(lock)
    lines = []
    for root in roots:
        top = os.path.join(home, root)
        if not os.path.isdir(top):
            continue
        recorded = {}
        for path, digest in found.items():
            if path.startswith(root + "/") and deployed(path):
                relative = path[len(root) + 1 :]
                recorded.setdefault(relative.split("/", 1)[0], {})[relative] = digest
        with os.scandir(top) as children:
            names = sorted(child.name for child in children)
        for name in names:
            expected = recorded.get(name)
            if not expected:
                continue
            try:
                files = entry_files(os.path.join(top, name))
                if files is None or files.keys() != expected.keys():
                    continue
                if any(file_digest(files[relative]) != digest for relative, digest in expected.items()):
                    continue
            except OSError:
                continue
            body = "".join(f"{digest}  {relative}\n" for digest, relative in sorted((d, r) for r, d in expected.items()))
            lines.append(f"{root}/{name}\t{hashlib.sha256(body.encode()).hexdigest()}")
    sys.stdout.write("".join(line + "\n" for line in sorted(lines)))


def main():
    if sys.argv[1] == "pristine":
        pristine(sys.argv[2], sys.argv[3], sys.argv[4:])
        return
    lines = sorted(f"{digest}  {path}" for path, digest in load_records(sys.argv[1]).items() if deployed(path))
    sys.stdout.write("".join(line + "\n" for line in lines))


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeDecodeError, ValueError, yaml.YAMLError) as error:
        print(f"lock-hashes: {error}", file=sys.stderr)
        sys.exit(1)
