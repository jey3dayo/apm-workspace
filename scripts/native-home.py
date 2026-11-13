#!/usr/bin/env python3
"""Kernel-held HOME operation lock and native output protection (Unix only)."""

import fcntl
import hashlib
import os
import stat
import subprocess
import sys
from pathlib import Path


def fail(message):
    raise RuntimeError(message)


def safe_directory(parent, name, *, create=False):
    if create:
        try:
            os.mkdir(name, 0o700, dir_fd=parent)
        except FileExistsError:
            pass
    descriptor = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    info = os.fstat(descriptor)
    if info.st_uid != os.geteuid() or info.st_mode & 0o022:
        os.close(descriptor)
        fail(f"unsafe native operation directory: {name}")
    return descriptor


def home_descriptor(home):
    if str(Path(home).resolve(strict=True)) != home:
        fail("native HOME must be its physical absolute path")
    descriptor = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    info = os.fstat(descriptor)
    if info.st_uid != os.geteuid() or info.st_mode & 0o022:
        os.close(descriptor)
        fail("native HOME must be owned by this user and not writable by other users")
    return descriptor


def operation_lock(home, *, create):
    root = home_descriptor(home)
    try:
        cache = safe_directory(root, ".cache", create=create)
    finally:
        os.close(root)
    try:
        flags = os.O_RDWR | os.O_NOFOLLOW
        if create:
            flags |= os.O_CREAT
        descriptor = os.open("apm-native-operation.lock", flags, 0o600, dir_fd=cache)
    finally:
        os.close(cache)
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        os.close(descriptor)
        fail("native operation lock must be an owner-only plain file with one link")
    inherited = os.environ.get("APM_NATIVE_LOCK_FD")
    if inherited:
        if not inherited.isdecimal() or int(inherited) < 3:
            os.close(descriptor)
            fail("invalid inherited native operation lock descriptor")
        inherited_fd = int(inherited)
        inherited_info = os.fstat(inherited_fd)
        if (info.st_dev, info.st_ino) != (inherited_info.st_dev, inherited_info.st_ino):
            os.close(descriptor)
            fail("inherited native operation lock belongs to another HOME")
        os.close(descriptor)
        descriptor = inherited_fd
    elif not create:
        os.close(descriptor)
        fail("native operation lock is not inherited")
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(descriptor)
        fail(f"another native operation is active for {home}; wait for it to finish")
    return descriptor


def check_opencode(home):
    descriptor = home_descriptor(home)
    try:
        for name in (".config", "opencode"):
            try:
                child = safe_directory(descriptor, name)
            except FileNotFoundError:
                return
            os.close(descriptor)
            descriptor = child
        try:
            info = os.stat("AGENTS.md", dir_fd=descriptor, follow_symlinks=False)
        except FileNotFoundError:
            return
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.geteuid():
            fail("OpenCode guide must be a plain file owned by this user with one link")
    finally:
        os.close(descriptor)


def check_design_rule(home, repository, source_ref):
    relative = ".claude/rules/claude-md-design.md"
    target = Path(home) / relative
    if not target.exists() and not target.is_symlink():
        return
    known = subprocess.run(
        ["git", "-C", repository, "cat-file", "-e", f"{source_ref}^{{commit}}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    if known.returncode:
        fail(f"cannot check {target}: source commit {source_ref} is not available in {repository}")
    instruction = "catalog/.apm/instructions/claude-md-design.instructions.md"
    listed = subprocess.run(
        ["git", "-C", repository, "ls-tree", source_ref, "--", instruction],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    if listed.returncode:
        fail(f"cannot inspect the pinned design instruction at {source_ref}")
    if not listed.stdout:
        return
    for path in (target.parent.parent, target.parent, target):
        if path.is_symlink():
            fail(f"scoped catalog rule must use plain paths: {path}")
    info = target.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        fail(f"scoped catalog rule must be a plain file with one link: {target}")
    content = target.read_bytes()
    source = subprocess.run(
        ["git", "-C", repository, "show", f"{source_ref}:{instruction}"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    if source.returncode:
        fail(f"cannot read the pinned design instruction at {source_ref}")
    parts = source.stdout.split(b"---\n", 2)
    scope = b'applyTo: "**/catalog/.apm/instructions/*.instructions.md"'
    if len(parts) != 3 or parts[0] or scope not in parts[1].splitlines():
        fail(f"cannot check {target}: the pinned design instruction has an unsupported scope")
    expected = b'---\npaths:\n  - "**/catalog/.apm/instructions/*.instructions.md"\n---\n\n' + parts[2].lstrip(b"\n")
    # The manual rule at f011e52 predates native instruction delivery; accept only its exact bytes.
    legacy_digest = "a841e2ca8eab805303d65e0acbb4cb6cdee0456120426b6e6e260388acef3fc0"
    if content == expected or hashlib.sha256(content).hexdigest() == legacy_digest:
        return
    fail(f"{target} differs from the pinned native rule and the pristine manual rule; "
         "compare and move it aside before retrying (docs/native-distribution.md). Nothing was overwritten")


def main():
    command, home, *arguments = sys.argv[1:]
    if command == "check-opencode":
        check_opencode(home)
        return 0
    if command == "check-design-rule":
        check_design_rule(home, *arguments)
        return 0
    if command not in ("run", "check"):
        fail("unknown native HOME command")
    descriptor = operation_lock(home, create=command == "run")
    if command == "check":
        return 0
    if not arguments:
        fail("native operation lock needs a command")
    environment = dict(os.environ, APM_NATIVE_LOCK_FD=str(descriptor))
    result = subprocess.run(arguments, env=environment, pass_fds=(descriptor,), check=False)
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: native HOME protection: {error}", file=sys.stderr)
        sys.exit(1)
