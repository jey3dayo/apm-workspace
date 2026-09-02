#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import tomllib
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

CONTRACTS_PATH = Path(__file__).with_name("audit_contracts.py")
CONTRACTS_SPEC = importlib.util.spec_from_file_location("audit_contracts", CONTRACTS_PATH)
if CONTRACTS_SPEC is None or CONTRACTS_SPEC.loader is None:
    raise RuntimeError(f"unable to load {CONTRACTS_PATH}")
CONTRACTS = importlib.util.module_from_spec(CONTRACTS_SPEC)
CONTRACTS_SPEC.loader.exec_module(CONTRACTS)
schedule_rrule = CONTRACTS.schedule_rrule
source_path = CONTRACTS.source_path

SUPPORTED_VERSION = 1
SUPPORTED_SCHEDULE_TYPES = {"daily", "weekly", "monthly"}
SUPPORTED_EXECUTION_ENVIRONMENTS = {"worktree"}
SUPPORTED_REASONING_EFFORTS = {"low", "medium", "high", "xhigh", "max"}
SUPPORTED_OPERATIONS = {"audit", "report"}
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
        'operation = "audit"\n'
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


def normalize_job_source(path: Path, repository_root: Path, prompts_root: Path) -> str:
    try:
        lexical_source = path.relative_to(repository_root).as_posix()
        resolved_path = path.resolve()
        resolved_path.relative_to(repository_root)
        resolved_path.relative_to(prompts_root.resolve())
    except (OSError, RuntimeError, ValueError) as error:
        raise ValidationError(f"{path}: job path resolves outside docs/prompts boundary") from error
    return lexical_source


def validate_job(
    path: Path,
    repository_root: Path,
    prompts_root: Path,
    default_reasoning_effort: str,
) -> dict[str, Any]:
    source = normalize_job_source(path, repository_root, prompts_root)
    name, metadata, body, weekdays_declared = parse_job(path)
    reject_unknown(
        metadata,
        {
            "id",
            "enabled",
            "operation",
            "schedule_type",
            "interval",
            "weekdays",
            "week_of_month",
            "time",
            "timezone",
            "reasoning_effort",
            "labels",
            "report_write_paths",
            "report_create_pull_request",
        },
        str(path),
    )
    if not name:
        raise ValidationError(f"{path}: H1 must be non-empty")
    if not body:
        raise ValidationError(f"{path}: body must be non-empty")
    job_id = require_string(metadata.get("id"), f"{path}: id")
    if not ID_PATTERN.fullmatch(job_id):
        raise ValidationError(f"{path}: id must be lower-case hyphen-case")
    operation = require_string(metadata.get("operation"), f"{path}: operation")
    if operation not in SUPPORTED_OPERATIONS:
        raise ValidationError(f"{path}: unsupported operation {operation}")
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
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise ValidationError(f"{path}: invalid timezone {timezone}") from error
    enabled = metadata.get("enabled")
    if not isinstance(enabled, bool):
        raise ValidationError(f"{path}: enabled must be boolean")
    interval = metadata.get("interval", 1)
    if not isinstance(interval, int) or isinstance(interval, bool):
        raise ValidationError(f"{path}: interval must be an integer")
    if interval <= 0:
        raise ValidationError(f"{path}: interval must be a positive integer")
    week_of_month = metadata.get("week_of_month")
    if "week_of_month" in metadata and (
        not isinstance(week_of_month, int) or isinstance(week_of_month, bool)
    ):
        raise ValidationError(f"{path}: week_of_month must be an integer")
    weekdays = metadata.get("weekdays", [])
    if not isinstance(weekdays, list) or any(not isinstance(day, str) for day in weekdays):
        raise ValidationError(f"{path}: weekdays must be an array of strings")
    if len(weekdays) != len(set(weekdays)):
        raise ValidationError(f"{path}: weekdays must be unique")
    if any(day not in SUPPORTED_WEEKDAYS for day in weekdays):
        raise ValidationError(f"{path}: weekdays contains an unsupported value")
    if schedule_type == "daily":
        if weekdays_declared:
            raise ValidationError(f"{path}: daily schedules cannot declare weekdays")
        if week_of_month is not None:
            raise ValidationError(f"{path}: daily schedules cannot use week_of_month")
    elif schedule_type == "weekly":
        if not weekdays:
            raise ValidationError(f"{path}: weekdays is required for weekly schedules")
        if week_of_month is not None:
            raise ValidationError(f"{path}: week_of_month is forbidden for weekly schedules")
    else:
        if "interval" in metadata:
            raise ValidationError(f"{path}: interval is forbidden for monthly schedules")
        if len(weekdays) != 1:
            raise ValidationError(f"{path}: monthly schedules require one weekday in weekdays")
        if week_of_month not in range(1, 6):
            raise ValidationError(f"{path}: week_of_month must be in range 1..5")
    try:
        rrule = schedule_rrule(
            schedule_type,
            weekdays,
            run_time,
            interval=interval,
            week_of_month=week_of_month,
        )
    except ValueError as error:
        raise ValidationError(f"{path}: schedule: {error}") from error
    reasoning_effort = default_reasoning_effort
    if "reasoning_effort" in metadata:
        reasoning_effort = require_string(
            metadata["reasoning_effort"], f"{path}: reasoning_effort"
        )
        if reasoning_effort not in SUPPORTED_REASONING_EFFORTS:
            raise ValidationError(
                f"{path}: reasoning_effort unsupported value {reasoning_effort}"
            )
    if operation == "report":
        if "labels" in metadata:
            raise ValidationError(f"{path}: labels are only allowed for audit jobs")
        labels = []
        if "report_write_paths" not in metadata:
            raise ValidationError(f"{path}: report_write_paths is required for report jobs")
        report_paths = require_string_array(
            metadata["report_write_paths"], f"{path}: report_write_paths"
        )
        report_write_paths = []
        seen_report_paths: set[str] = set()
        for report_path in report_paths:
            try:
                normalized_path = source_path(str(repository_root), report_path)
            except (OSError, RuntimeError, ValueError) as error:
                raise ValidationError(
                    f"{path}: report_write_paths: {error}"
                ) from error
            resolved_path = (repository_root / normalized_path).resolve()
            if resolved_path.is_dir():
                raise ValidationError(
                    f"{path}: report_write_paths must not contain directories"
                )
            if normalized_path in seen_report_paths:
                raise ValidationError(
                    f"{path}: report_write_paths must contain unique normalized paths"
                )
            seen_report_paths.add(normalized_path)
            report_write_paths.append(normalized_path)
        report_create_pull_request = metadata.get("report_create_pull_request", False)
        if not isinstance(report_create_pull_request, bool):
            raise ValidationError(f"{path}: report_create_pull_request must be boolean")
    else:
        labels = [] if "labels" not in metadata else require_string_array(metadata["labels"], f"{path}: labels")
        if "report_write_paths" in metadata:
            raise ValidationError(f"{path}: report_write_paths is only allowed for report jobs")
        if "report_create_pull_request" in metadata:
            raise ValidationError(
                f"{path}: report_create_pull_request is only allowed for report jobs"
            )
        report_write_paths = []
        report_create_pull_request = False
    return {
        "id": job_id,
        "name": name,
        "enabled": enabled,
        "operation": operation,
        "schedule_type": schedule_type,
        "interval": interval,
        "weekdays": weekdays,
        "week_of_month": week_of_month,
        "time": run_time,
        "timezone": timezone,
        "reasoning_effort": reasoning_effort,
        "report_write_paths": report_write_paths,
        "report_create_pull_request": report_create_pull_request,
        "rrule": rrule,
        "source": source,
        "prompt": body,
        "labels": labels,
    }


def validate_repository(root: Path) -> dict[str, Any]:
    root = root.resolve()
    prompts = root / "docs" / "prompts"
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
    default_reasoning_effort = require_string(
        defaults.get("reasoning_effort"),
        "automation.defaults.reasoning_effort",
    )
    jobs = [
        validate_job(path, root, prompts, default_reasoning_effort)
        for path in sorted(prompts.glob("*.md"))
    ]
    if not jobs:
        raise ValidationError("at least one job Markdown file is required")
    ids = [job["id"] for job in jobs]
    duplicate_ids = sorted({job_id for job_id in ids if ids.count(job_id) > 1})
    if duplicate_ids:
        raise ValidationError(f"duplicate job id: {', '.join(duplicate_ids)}")
    global_labels = base_labels + list(severity.values()) + list(priority.values())
    for job in jobs:
        job["preflight_labels"] = (
            global_labels + job["labels"] if job["operation"] == "audit" else []
        )
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
