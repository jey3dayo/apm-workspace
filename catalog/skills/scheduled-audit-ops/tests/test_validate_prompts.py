from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "validate_prompts.py"
SPEC = importlib.util.spec_from_file_location("validate_prompts", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ValidatePromptsTest(unittest.TestCase):
    def write_repo(self, config: str, jobs: dict[str, str]) -> Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        prompts = root / "docs" / "prompts"
        prompts.mkdir(parents=True)
        (prompts / "config.toml").write_text(config, encoding="utf-8")
        for name, body in jobs.items():
            (prompts / name).write_text(body, encoding="utf-8")
        return root

    def test_normalizes_daily_weekly_and_disabled_jobs(self) -> None:
        root = self.write_repo(
            '''
version = 1
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
''',
            {
                "performance.md": '''# Performance Audit

<!-- scheduled-audit-config -->

```toml
id = "performance-audit"
enabled = true
schedule_type = "weekly"
weekdays = ["monday"]
time = "10:00"
timezone = "Asia/Tokyo"
```

## Prompt

Inspect performance.
''',
                "security.md": '''# Security Audit

<!-- scheduled-audit-config -->

```toml
id = "security-audit"
enabled = false
schedule_type = "daily"
time = "11:30"
timezone = "Asia/Tokyo"
```

## Prompt

Inspect security.
''',
            },
        )

        result = MODULE.validate_repository(root)

        self.assertEqual(result["version"], 1)
        self.assertEqual(
            [job["id"] for job in result["jobs"]],
            ["performance-audit", "security-audit"],
        )
        self.assertEqual(result["jobs"][0]["weekdays"], ["monday"])
        self.assertFalse(result["jobs"][1]["enabled"])

    def test_rejects_duplicate_ids(self) -> None:
        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG,
            {
                "one.md": MODULE.example_job("same-id"),
                "two.md": MODULE.example_job("same-id"),
            },
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "duplicate job id"):
            MODULE.validate_repository(root)

    def test_rejects_repository_without_jobs(self) -> None:
        root = self.write_repo(MODULE.EXAMPLE_CONFIG, {})

        with self.assertRaisesRegex(MODULE.ValidationError, "at least one job"):
            MODULE.validate_repository(root)

    def test_rejects_missing_weekdays_for_weekly_job(self) -> None:
        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG,
            {"bad.md": MODULE.example_job("bad", weekdays=None)},
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "weekdays"):
            MODULE.validate_repository(root)

    def test_rejects_invalid_timezone(self) -> None:
        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG,
            {"bad.md": MODULE.example_job("bad", timezone="Moon/Base")},
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "timezone"):
            MODULE.validate_repository(root)

    def test_rejects_unsupported_version(self) -> None:
        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG.replace("version = 1", "version = 2"),
            {},
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "version"):
            MODULE.validate_repository(root)


if __name__ == "__main__":
    unittest.main()
