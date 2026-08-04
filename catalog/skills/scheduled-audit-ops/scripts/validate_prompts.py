#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import tomllib
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

SUPPORTED_VERSION = 1
SUPPORTED_SCHEDULE_TYPES = {"daily", "weekly"}
SUPPORTED_WEEKDAYS = {
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
}
ID_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TIME_PATTERN = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")
JOB_PATTERN = re.compile(
    r"\A# (?P<name>[^\n]+)\n+"
    r".*?<!-- scheduled-audit-config -->\s*"
    r"```toml\n(?P<config>.*?)\n```\s*"
    r"## Prompt\s*(?P<body>.+)\Z",
    re.DOTALL,
)


class ValidationError(ValueError):
    pass


EXAMPLE_CONFIG = '''version = 1
[automation.defaults]
execution_environment = "worktree"
reasoning_effort = "high"
notification_policy = "failed_runs_only"
[issues]
mode = "create_or_update"
base_labels = ["task"]
dedupe_marker_prefix = "scheduled-audit"
[issues.severity_labels]
high = "Severity: High"
medium = "Severity: Medium"
low = "Severity: Low"
[issues.priority_labels]
p1 = "priority/P1"
p2 = "priority/P2"
p3 = "priority/P3"
'''


def example_job(
    job_id: str,
    *,
    weekdays: tuple[str, ...] | None = ("monday",),
    timezone: str = "Asia/Tokyo",
) -> str:
    weekday_line = "" if weekdays is None else f"weekdays = {json.dumps(weekdays)}\n"
    return (
        "# Example\n\n"
        "<!-- scheduled-audit-config -->\n\n"
        "```toml\n"
        f'id = "{job_id}"\n'
        "enabled = true\n"
        'schedule_type = "weekly"\n'
        f"{weekday_line}"
        'time = "10:00"\n'
        f'timezone = "{timezone}"\n'
        "```\n\n"
        "## Prompt\n\n"
        "Inspect the repository.\n"
    )


def require_mapping(value: object, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{field} must be a TOML table")
    return value


def require_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{field} must be a non-empty string")
    return value.strip()


def parse_job(path: Path) -> tuple[str, dict[str, Any], str]:
    text = path.read_text(encoding="utf-8")
    matched = JOB_PATTERN.fullmatch(text.strip())
    if not matched:
        raise ValidationError(
            f"{path}: expected H1, scheduled-audit-config TOML block, and Prompt section"
        )
    name = matched.group("name").strip()
    metadata = tomllib.loads(matched.group("config"))
    body = matched.group("body").strip()
    return name, metadata, body


def validate_job(path: Path) -> dict[str, Any]:
    name, metadata, body = parse_job(path)
    job_id = require_string(metadata.get("id"), f"{path}: id")
    if not ID_PATTERN.fullmatch(job_id):
        raise ValidationError(f"{path}: id must be lower-case hyphen-case")
    schedule_type = require_string(
        metadata.get("schedule_type"), f"{path}: schedule_type"
    )
    if schedule_type not in SUPPORTED_SCHEDULE_TYPES:
        raise ValidationError(f"{path}: unsupported schedule_type {schedule_type}")
    run_time = require_string(metadata.get("time"), f"{path}: time")
    if not TIME_PATTERN.fullmatch(run_time):
        raise ValidationError(f"{path}: time must be HH:MM")
    timezone = require_string(metadata.get("timezone"), f"{path}: timezone")
    try:
        ZoneInfo(timezone)
    except ZoneInfoNotFoundError as error:
        raise ValidationError(f"{path}: invalid timezone {timezone}") from error
    enabled = metadata.get("enabled")
    if not isinstance(enabled, bool):
        raise ValidationError(f"{path}: enabled must be boolean")
    weekdays = metadata.get("weekdays", [])
    if schedule_type == "weekly" and not weekdays:
        raise ValidationError(f"{path}: weekdays is required for weekly schedules")
    if not isinstance(weekdays, list) or any(
        day not in SUPPORTED_WEEKDAYS for day in weekdays
    ):
        raise ValidationError(f"{path}: weekdays contains an unsupported value")
    return {
        "id": job_id,
        "name": name,
        "enabled": enabled,
        "schedule_type": schedule_type,
        "weekdays": weekdays,
        "time": run_time,
        "timezone": timezone,
        "source": str(path),
        "prompt": body,
    }


def validate_repository(root: Path) -> dict[str, Any]:
    prompts = root.resolve() / "docs" / "prompts"
    config_path = prompts / "config.toml"
    if not config_path.is_file():
        raise ValidationError(f"missing {config_path}")
    config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    if config.get("version") != SUPPORTED_VERSION:
        raise ValidationError(f"unsupported config version: {config.get('version')}")
    automation = require_mapping(config.get("automation"), "automation")
    defaults = require_mapping(automation.get("defaults"), "automation.defaults")
    issues = require_mapping(config.get("issues"), "issues")
    severity = require_mapping(issues.get("severity_labels"), "issues.severity_labels")
    priority = require_mapping(issues.get("priority_labels"), "issues.priority_labels")
    for key in ("execution_environment", "reasoning_effort", "notification_policy"):
        require_string(defaults.get(key), f"automation.defaults.{key}")
    for key in ("mode", "dedupe_marker_prefix"):
        require_string(issues.get(key), f"issues.{key}")
    if not isinstance(issues.get("base_labels"), list):
        raise ValidationError("issues.base_labels must be an array")
    for key in ("high", "medium", "low"):
        require_string(severity.get(key), f"issues.severity_labels.{key}")
    for key in ("p1", "p2", "p3"):
        require_string(priority.get(key), f"issues.priority_labels.{key}")
    jobs = [validate_job(path) for path in sorted(prompts.glob("*.md"))]
    ids = [job["id"] for job in jobs]
    duplicate_ids = sorted({job_id for job_id in ids if ids.count(job_id) > 1})
    if duplicate_ids:
        raise ValidationError(f"duplicate job id: {', '.join(duplicate_ids)}")
    return {"version": SUPPORTED_VERSION, "config": config, "jobs": jobs}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repository", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(validate_repository(args.repository), ensure_ascii=False, indent=2))
    except (OSError, tomllib.TOMLDecodeError, ValidationError) as error:
        parser.exit(1, f"scheduled-audit validation failed: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
