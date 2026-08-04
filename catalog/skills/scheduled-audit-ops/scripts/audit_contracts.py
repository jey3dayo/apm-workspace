"""Pure, stdlib-only algorithms shared by scheduled-audit implementations."""

from __future__ import annotations

import hashlib
import posixpath
import re
from pathlib import Path
from typing import NamedTuple


_PREFIX = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")


def repository_remote_slug(remote: str) -> str:
    value = remote.strip().replace("\\", "/")
    value = re.sub(r"^ssh://[^/]+/", "", value, flags=re.IGNORECASE)
    value = re.sub(r"^https?://[^/]+/", "", value, flags=re.IGNORECASE)
    value = re.sub(r"^[^/:]+@[^:]+:", "", value)
    value = value.removesuffix(".git")
    parts = [part for part in value.split("/") if part and part != "."]
    if len(parts) < 2 or any(part == ".." for part in parts):
        raise ValueError("remote must contain owner and repository")
    return "/".join(parts[-2:]).lower()


def source_path(repository_root: str, file_path: str) -> str:
    root = Path(repository_root).resolve()
    candidate_text = file_path.replace("\\", "/")
    candidate = Path(candidate_text)
    if candidate.is_absolute():
        raise ValueError("source path must be repository-relative")
    resolved = (root / candidate_text).resolve()
    try:
        relative = resolved.relative_to(root)
    except ValueError as error:
        raise ValueError("source path escapes repository") from error
    normalized = posixpath.normpath(relative.as_posix())
    if normalized in ("", ".") or normalized.startswith("../"):
        raise ValueError("source path escapes repository")
    return normalized


def source_identity(remote: str, source_path_value: str, job_id: str) -> str:
    candidate = source_path_value.replace("\\", "/")
    if candidate.startswith("/"):
        raise ValueError("source path must be repository-relative")
    parts: list[str] = []
    for part in candidate.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                raise ValueError("source path escapes repository")
            parts.pop()
            continue
        parts.append(part)
    if not parts:
        raise ValueError("source path must not be empty")
    normalized_source = "/".join(parts)
    return f"v1:{repository_remote_slug(remote)}:{normalized_source}:{job_id}"


def job_id_source_identity(remote: str, prompt_path: str, job_id: str) -> str:
    return source_identity(remote, prompt_path, job_id)


def _validate_prefix(prefix: str) -> None:
    if not _PREFIX.fullmatch(prefix):
        raise ValueError("prefix must be lower-case hyphen format")


def source_marker(prefix: str, remote: str, source_path_value: str, job_id: str) -> str:
    _validate_prefix(prefix)
    return f"<!-- {prefix}:source:{source_identity(remote, source_path_value, job_id)} -->"


def finding_fingerprint(job_id: str, category: str, stable_owner: str, behavior_key: str) -> str:
    payload = "\x1f".join((job_id, category, stable_owner, behavior_key)).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def issue_marker(prefix: str, job_id: str, fingerprint: str) -> str:
    _validate_prefix(prefix)
    return f"<!-- {prefix}:{job_id}:{fingerprint} -->"


def lifecycle_disposition(*, finding_present: bool, issue_state: str | None, evidence_sufficient: bool, changed: bool = False) -> str:
    states = {None, "open", "closed", "rejected"}
    if issue_state not in states:
        raise ValueError("invalid issue state")
    if not evidence_sufficient:
        if finding_present and issue_state == "open" and changed:
            raise ValueError("changed finding cannot be acted on without evidence")
        return "hold"
    if issue_state == "rejected":
        return "suppress"
    if not finding_present:
        if issue_state == "open":
            return "close"
        if issue_state is not None:
            raise ValueError("absent finding requires an open issue or no issue")
        return "unchanged"
    if issue_state is None:
        return "create"
    if issue_state == "closed":
        return "reopen"
    return "update" if changed else "unchanged"


class IssueRecord(NamedTuple):
    number: int
    source_identity: str


class Reconciliation(NamedTuple):
    canonical: IssueRecord | None
    duplicate_numbers: tuple[int, ...]
    preferred_writer: str | None


def reconcile_issues(records: list[IssueRecord] | tuple[IssueRecord, ...]) -> Reconciliation:
    if any(record.number <= 0 for record in records):
        raise ValueError("Issue numbers must be positive")
    ordered = sorted(records, key=lambda record: (record.number, record.source_identity))
    canonical = ordered[0] if ordered else None
    unique_numbers = sorted({record.number for record in records})
    duplicates = tuple(unique_numbers[1:])
    preferred = min((record.source_identity for record in records), default=None)
    return Reconciliation(canonical, duplicates, preferred)


def reconcile_duplicates(issue_ids: list[str]) -> list[str]:
    return sorted(set(issue_ids))


def single_writer_winner(issue_ids: list[str]) -> str | None:
    return min(issue_ids) if issue_ids else None
