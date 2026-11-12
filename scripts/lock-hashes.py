#!/usr/bin/env python3
"""Prints "<sha256>  <path>" for every deployed_file_hashes record of an apm.lock.yaml, sorted.

Only the top-level dependencies' deployed_file_hashes mappings are read, as YAML structure. Anything unexpected exits
non-zero (nothing is printed), so a caller that approves from this output approves nothing from a lock it cannot trust.
Needs PyYAML; run it with the interpreter apm itself runs on.
"""

import re
import sys

import yaml

HASH = re.compile(r"sha256:([0-9a-f]{64})")


class StrictLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        keys = [self.construct_object(key, deep=True) for key, _ in node.value]
        if len(set(map(repr, keys))) != len(keys):
            raise ValueError(f"duplicate key in the mapping at line {node.start_mark.line + 1}")
        return super().construct_mapping(node, deep)


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
            if not isinstance(path, str) or not path or "\n" in path:
                fail(f"unusable path: {path!r}")
            match = HASH.fullmatch(value) if isinstance(value, str) else None
            if match is None:
                fail(f"{path}: the value is not sha256:<64 lowercase hex>")
            if found.setdefault(path, match.group(1)) != match.group(1):
                fail(f"{path} is recorded with different hashes")
    return found


def main():
    with open(sys.argv[1], encoding="utf-8") as handle:
        found = records(yaml.load(handle, Loader=StrictLoader))
    lines = sorted(
        f"{digest}  {path}"
        for path, digest in found.items()
        if "/__pycache__/" not in path and path.rsplit("/", 1)[-1] != ".apm-pin"
    )
    sys.stdout.write("".join(line + "\n" for line in lines))


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeDecodeError, ValueError, yaml.YAMLError) as error:
        print(f"lock-hashes: {error}", file=sys.stderr)
        sys.exit(1)
