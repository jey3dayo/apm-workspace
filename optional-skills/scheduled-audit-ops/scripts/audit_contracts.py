"""Pure, stdlib-only algorithms shared by scheduled-audit implementations."""

from __future__ import annotations

import hashlib
import posixpath
import re
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import NamedTuple


_PREFIX = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")
_WEEKDAY_CODES = {
    "monday": "MO",
    "tuesday": "TU",
    "wednesday": "WE",
    "thursday": "TH",
    "friday": "FR",
    "saturday": "SA",
    "sunday": "SU",
}


def schedule_rrule(
    schedule_type: str,
    weekdays: Sequence[str],
    run_time: str,
    *,
    interval: int = 1,
    week_of_month: int | None = None,
) -> str:
    hour_text, minute_text = run_time.split(":", maxsplit=1)
    hour, minute = int(hour_text), int(minute_text)
    if interval <= 0:
        raise ValueError("interval must be a positive integer")
    try:
        days = ",".join(_WEEKDAY_CODES[day] for day in weekdays)
    except KeyError as error:
        raise ValueError("unsupported weekday") from error
    if schedule_type == "daily":
        if weekdays or week_of_month is not None:
            raise ValueError("daily schedule cannot use weekday fields")
        return f"FREQ=DAILY;INTERVAL={interval};BYHOUR={hour};BYMINUTE={minute}"
    if schedule_type == "weekly":
        if not weekdays or week_of_month is not None:
            raise ValueError("weekly schedule requires weekdays only")
        return f"FREQ=WEEKLY;INTERVAL={interval};BYDAY={days};BYHOUR={hour};BYMINUTE={minute}"
    if schedule_type == "monthly":
        if interval != 1 or len(weekdays) != 1 or week_of_month not in range(1, 6):
            raise ValueError("monthly schedule requires one weekday and week_of_month 1..5")
        return f"FREQ=MONTHLY;BYDAY={days};BYSETPOS={week_of_month};BYHOUR={hour};BYMINUTE={minute}"
    raise ValueError(f"unsupported schedule type: {schedule_type}")


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


def marker_candidates(canonical_marker: str, legacy_markers: Sequence[str] = ()) -> tuple[str, ...]:
    markers = (canonical_marker, *legacy_markers)
    if any(not isinstance(marker, str) or not marker or marker != marker.strip() for marker in markers):
        raise ValueError("markers must be non-empty exact strings")
    return tuple(dict.fromkeys(markers))


def matching_issue_numbers(issue_bodies: Mapping[int, str], markers: Sequence[str]) -> tuple[int, ...]:
    candidates = marker_candidates(markers[0], markers[1:]) if markers else ()
    if not candidates:
        raise ValueError("at least one marker is required")
    for number, body in issue_bodies.items():
        if not isinstance(number, int) or number <= 0:
            raise ValueError("Issue numbers must be positive")
        if not isinstance(body, str):
            raise ValueError("Issue bodies must be strings")
    return tuple(
        sorted(number for number, body in issue_bodies.items() if any(marker in body for marker in candidates))
    )


def migrate_issue_body(body: str, canonical_marker: str, searched_markers: Sequence[str]) -> str:
    if not isinstance(body, str):
        raise ValueError("Issue body must be a string")
    markers = marker_candidates(canonical_marker, searched_markers)
    without_markers = body
    for marker in markers:
        without_markers = without_markers.replace(marker, "")
    remainder = without_markers.strip()
    return canonical_marker if not remainder else f"{canonical_marker}\n{remainder}"


def lifecycle_disposition(*, finding_present: bool, issue_state: str | None, evidence_sufficient: bool, changed: bool = False) -> str:
    if any(not isinstance(value, bool) for value in (finding_present, evidence_sufficient, changed)):
        raise ValueError("lifecycle booleans must be boolean")
    states = {None, "open", "closed", "rejected"}
    if issue_state not in states:
        raise ValueError("invalid issue state")
    if changed and not finding_present:
        raise ValueError("changed finding must be present")
    if changed and not evidence_sufficient:
        raise ValueError("changed finding requires sufficient evidence")
    if changed and issue_state not in {"open", "closed"}:
        raise ValueError("changed finding requires an open or closed issue")
    if not finding_present and issue_state in {"closed", "rejected"}:
        raise ValueError("absent finding requires an open issue or no issue")
    if not evidence_sufficient:
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


def reconcile_issues(records: list[IssueRecord] | tuple[IssueRecord, ...]) -> Reconciliation:
    if any(record.number <= 0 for record in records):
        raise ValueError("Issue numbers must be positive")
    ordered = sorted(records, key=lambda record: (record.number, record.source_identity))
    canonical = ordered[0] if ordered else None
    unique_numbers = sorted({record.number for record in records})
    duplicates = tuple(number for number in unique_numbers if canonical is not None and number != canonical.number)
    return Reconciliation(canonical, duplicates)


def preferred_source_writer(source_identities: Sequence[str]) -> str | None:
    if any(not isinstance(identity, str) or not identity for identity in source_identities):
        raise ValueError("source identities must be non-empty strings")
    return min(set(source_identities), default=None)
