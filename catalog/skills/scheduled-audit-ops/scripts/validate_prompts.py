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
SUPPORTED_EXECUTION_ENVIRONMENTS = {"worktree"}
SUPPORTED_REASONING_EFFORTS = {"low", "medium", "high"}
SUPPORTED_NOTIFICATION_POLICIES = {"always", "failed_runs_only", "never"}
SUPPORTED_ISSUE_MODES = {"create_or_update"}
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
MARKER_PREFIX_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
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


def require_string_array(value: object, field: str) -> list[str]:
    if not isinstance(value, list) or not value or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise ValidationError(f"{field} must be a non-empty array of non-empty strings")
    result = [item.strip() for item in value]
    if len(result) != len(set(result)):
        raise ValidationError(f"{field} must contain unique strings")
    return result


def reject_unknown(mapping: dict[str, Any], allowed: set[str], field: str) -> None:
    unknown = sorted(set(mapping) - allowed)
    if unknown:
        raise ValidationError(f"{field} has unknown key(s): {', '.join(unknown)}")


def parse_job(path: Path) -> tuple[str, dict[str, Any], str, bool]:
    text = path.read_text(encoding="utf-8")
    matched = JOB_PATTERN.fullmatch(text.strip())
    if not matched:
        raise ValidationError(
            f"{path}: expected H1, scheduled-audit-config TOML block, and Prompt section"
        )
    name = matched.group("name").strip()
    metadata = tomllib.loads(matched.group("config"))
    body = matched.group("body").strip()
    return name, metadata, body, "weekdays" in metadata


def validate_job(path: Path) -> dict[str, Any]:
    name, metadata, body, weekdays_declared = parse_job(path)
    reject_unknown(
        metadata,
        {"id", "enabled", "schedule_type", "weekdays", "time", "timezone", "labels"},
        str(path),
    )
    if not name:
        raise ValidationError(f"{path}: H1 must be non-empty")
    if not body:
        raise ValidationError(f"{path}: body must be non-empty")
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
    if not isinstance(weekdays, list) or any(not isinstance(day, str) for day in weekdays):
        raise ValidationError(f"{path}: weekdays must be an array of strings")
    if schedule_type == "weekly" and not weekdays:
        raise ValidationError(f"{path}: weekdays is required for weekly schedules")
    if schedule_type == "daily" and weekdays_declared:
        raise ValidationError(f"{path}: weekdays is forbidden for daily schedules")
    if len(weekdays) != len(set(weekdays)):
        raise ValidationError(f"{path}: weekdays must be unique")
    if any(day not in SUPPORTED_WEEKDAYS for day in weekdays):
        raise ValidationError(f"{path}: weekdays contains an unsupported value")
    labels = [] if "labels" not in metadata else require_string_array(metadata["labels"], f"{path}: labels")
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
        "labels": labels,
    }


def validate_repository(root: Path) -> dict[str, Any]:
    prompts = root.resolve() / "docs" / "prompts"
    config_path = prompts / "config.toml"
    if not config_path.is_file():
        raise ValidationError(f"missing {config_path}")
    config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    reject_unknown(config, {"version", "automation", "issues"}, "config")
    if config.get("version") != SUPPORTED_VERSION:
        raise ValidationError(f"unsupported config version: {config.get('version')}")
    automation = require_mapping(config.get("automation"), "automation")
    reject_unknown(automation, {"defaults"}, "automation")
    defaults = require_mapping(automation.get("defaults"), "automation.defaults")
    issues = require_mapping(config.get("issues"), "issues")
    reject_unknown(defaults, {"execution_environment", "reasoning_effort", "notification_policy"}, "automation.defaults")
    reject_unknown(issues, {"mode", "base_labels", "dedupe_marker_prefix", "severity_labels", "priority_labels"}, "issues")
    severity = require_mapping(issues.get("severity_labels"), "issues.severity_labels")
    priority = require_mapping(issues.get("priority_labels"), "issues.priority_labels")
    for key, allowed in {
        "execution_environment": SUPPORTED_EXECUTION_ENVIRONMENTS,
        "reasoning_effort": SUPPORTED_REASONING_EFFORTS,
        "notification_policy": SUPPORTED_NOTIFICATION_POLICIES,
    }.items():
        value = require_string(defaults.get(key), f"automation.defaults.{key}")
        if value not in allowed:
            raise ValidationError(f"automation.defaults.{key} unsupported value {value}")
    mode = require_string(issues.get("mode"), "issues.mode")
    if mode not in SUPPORTED_ISSUE_MODES:
        raise ValidationError(f"issues.mode unsupported value {mode}")
    prefix = require_string(issues.get("dedupe_marker_prefix"), "issues.dedupe_marker_prefix")
    if not MARKER_PREFIX_PATTERN.fullmatch(prefix):
        raise ValidationError("issues.dedupe_marker_prefix must be lower-case hyphen format")
    base_labels = require_string_array(issues.get("base_labels"), "issues.base_labels")
    reject_unknown(severity, {"high", "medium", "low"}, "issues.severity_labels")
    reject_unknown(priority, {"p1", "p2", "p3"}, "issues.priority_labels")
    for key in ("high", "medium", "low"):
        require_string(severity.get(key), f"issues.severity_labels.{key}")
    for key in ("p1", "p2", "p3"):
        require_string(priority.get(key), f"issues.priority_labels.{key}")
    jobs = [validate_job(path) for path in sorted(prompts.glob("*.md"))]
    if not jobs:
        raise ValidationError("at least one job Markdown file is required")
    ids = [job["id"] for job in jobs]
    duplicate_ids = sorted({job_id for job_id in ids if ids.count(job_id) > 1})
    if duplicate_ids:
        raise ValidationError(f"duplicate job id: {', '.join(duplicate_ids)}")
    global_labels = base_labels + list(severity.values()) + list(priority.values())
    for job in jobs:
        job["preflight_labels"] = global_labels + job["labels"]
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
