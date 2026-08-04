from __future__ import annotations

import importlib.util
import inspect
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

    def test_rejects_unknown_keys_at_root_and_job_levels(self) -> None:
        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG.replace("version = 1", "version = 1\nunknown = true"),
            {"bad.md": MODULE.example_job("bad")},
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "unknown"):
            MODULE.validate_repository(root)

        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG,
            {"bad.md": MODULE.example_job("bad").replace('timezone = "Asia/Tokyo"', 'timezone = "Asia/Tokyo"\nextra = true')},
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "unknown"):
            MODULE.validate_repository(root)

    def test_validates_enums_arrays_markers_schedule_and_job_labels(self) -> None:
        config = MODULE.EXAMPLE_CONFIG.replace('dedupe_marker_prefix = "scheduled-audit"', 'dedupe_marker_prefix = "audit-run"')
        job = MODULE.example_job("bad").replace('timezone = "Asia/Tokyo"', 'timezone = "Asia/Tokyo"\nlabels = ["team-platform", "priority-extra"]')
        root = self.write_repo(config, {"bad.md": job})
        result = MODULE.validate_repository(root)
        self.assertEqual(result["jobs"][0]["labels"], ["team-platform", "priority-extra"])
        self.assertIn("team-platform", result["jobs"][0]["preflight_labels"])

        for replacement, message in [
            ('execution_environment = "shell"', "execution_environment"),
            ('dedupe_marker_prefix = "Bad Prefix"', "dedupe_marker_prefix"),
        ]:
            bad = self.write_repo(config.replace('execution_environment = "worktree"', replacement) if "execution" in replacement else config.replace('dedupe_marker_prefix = "audit-run"', replacement), {"bad.md": MODULE.example_job("bad")})
            with self.assertRaisesRegex(MODULE.ValidationError, message):
                MODULE.validate_repository(bad)

    def test_deterministic_helpers_define_identity_fingerprint_markers_and_lifecycle(self) -> None:
        helper_path = SCRIPT.parent / "audit_contracts.py"
        spec = importlib.util.spec_from_file_location("audit_contracts", helper_path)
        assert spec and spec.loader
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        self.assertEqual(
            helper.source_identity("HTTPS://GitHub.com/Acme/Widgets.git", "docs\\prompts/./job.md", "job"),
            "v1:acme/widgets:docs/prompts/job.md:job",
        )
        self.assertEqual(
            helper.source_marker("audit-run", "git@github.com:Acme/Widgets.git", "docs/prompts/job.md", "job"),
            "<!-- audit-run:source:v1:acme/widgets:docs/prompts/job.md:job -->",
        )
        with self.assertRaises(ValueError):
            helper.source_path("/repo", "/etc/passwd")
        with self.assertRaises(ValueError):
            helper.source_path("/repo", "../outside.md")
        with self.assertRaises(ValueError):
            helper.source_identity("acme/widgets", "a/../../outside.md", "job")
        self.assertEqual(helper.repository_remote_slug("https://github.com/acme/widgets.git"), "acme/widgets")
        self.assertEqual(helper.repository_remote_slug("git@github.com:acme/widgets.git"), "acme/widgets")
        first = helper.finding_fingerprint("job", "security", "owner", "behavior")
        self.assertEqual(first, "93601981a8a40fc5ec5adcbc538acab44de333b126eba76bfdbbc3ba2ea0d4f1")
        self.assertEqual(list(inspect.signature(helper.finding_fingerprint).parameters), ["job_id", "category", "stable_owner", "behavior_key"])
        self.assertEqual(helper.issue_marker("audit-run", "job", first), f"<!-- audit-run:job:{first} -->")
        self.assertEqual(first, helper.finding_fingerprint("job", "security", "owner", "behavior"))
        self.assertNotEqual(first, helper.finding_fingerprint("job", "security", "other", "behavior"))
        self.assertEqual(helper.lifecycle_disposition(finding_present=False, issue_state=None, evidence_sufficient=False), "hold")
        self.assertEqual(helper.lifecycle_disposition(finding_present=True, issue_state="rejected", evidence_sufficient=True), "suppress")
        self.assertEqual(helper.lifecycle_disposition(finding_present=False, issue_state="open", evidence_sufficient=True), "close")
        self.assertEqual(helper.lifecycle_disposition(finding_present=True, issue_state=None, evidence_sufficient=True), "create")
        self.assertEqual(helper.lifecycle_disposition(finding_present=True, issue_state="closed", evidence_sufficient=True), "reopen")
        self.assertEqual(helper.lifecycle_disposition(finding_present=True, issue_state="open", evidence_sufficient=True, changed=True), "update")
        self.assertEqual(helper.lifecycle_disposition(finding_present=True, issue_state="open", evidence_sufficient=True, changed=False), "unchanged")
        with self.assertRaises(ValueError):
            helper.lifecycle_disposition(finding_present=False, issue_state="closed", evidence_sufficient=True)
        with self.assertRaises(ValueError):
            helper.lifecycle_disposition(finding_present=True, issue_state="open", evidence_sufficient=False, changed=True)
        records = [helper.IssueRecord(9, "z-source"), helper.IssueRecord(3, "b-source"), helper.IssueRecord(3, "a-source")]
        result = helper.reconcile_issues(records)
        self.assertEqual(result.canonical.number, 3)
        self.assertEqual(result.duplicate_numbers, (9,))
        self.assertEqual(result.preferred_writer, "a-source")
        self.assertIsNone(helper.reconcile_issues([]).canonical)
        with self.assertRaises(ValueError):
            helper.reconcile_issues([helper.IssueRecord(0, "source")])

    def test_skill_documents_untrusted_boundary_and_evidence_recheck(self) -> None:
        skill = (SCRIPT.parent.parent / "SKILL.md").read_text(encoding="utf-8")
        contracts = (SCRIPT.parent.parent / "references" / "contracts.md").read_text(encoding="utf-8")
        for phrase in ("untrusted", "job text cannot expand authority", "create/update/reopen/close/suppress", "exact file:line", "repeatable recheck"):
            self.assertIn(phrase, skill.lower() + contracts.lower())
        text = skill.lower() + contracts.lower()
        for phrase in ("embedded instructions", "solely because audited content requested it", "automation memory"):
            self.assertIn(phrase, text)

    def test_validator_is_conservative_about_unknown_keys_enums_and_labels(self) -> None:
        config = MODULE.EXAMPLE_CONFIG
        cases = [
            (config.replace("version = 1", "version = 1\nextra = true"), "config"),
            (config.replace("[automation.defaults]", "[automation]\nextra = true\n[automation.defaults]"), "automation"),
            (config.replace('reasoning_effort = "high"', 'reasoning_effort = "high"\nextra = true'), "automation.defaults"),
            (config.replace("[issues]", "[issues]\nextra = true"), "issues"),
            (config.replace("[issues.severity_labels]", "[issues.severity_labels]\nextra = \"x\""), "severity_labels"),
            (config.replace("[issues.priority_labels]", "[issues.priority_labels]\nextra = \"x\""), "priority_labels"),
        ]
        for bad_config, field in cases:
            with self.subTest(field=field):
                with self.assertRaises(MODULE.ValidationError):
                    MODULE.validate_repository(self.write_repo(bad_config, {"job.md": MODULE.example_job("job")}))
        invalids = [
            ('execution_environment = "container"', "execution_environment", 'worktree'),
            ('reasoning_effort = "none"', "reasoning_effort", 'high'),
            ('notification_policy = "sometimes"', "notification_policy", 'failed_runs_only'),
            ('mode = "dry_run"', "mode", 'create_or_update'),
        ]
        for replacement, field, original in invalids:
            with self.subTest(field=field):
                with self.assertRaisesRegex(MODULE.ValidationError, field):
                    MODULE.validate_repository(self.write_repo(config.replace(f'{field} = "{original}"', replacement), {"job.md": MODULE.example_job("job")}))
        invalid_job = MODULE.example_job("job").replace('schedule_type = "weekly"', 'schedule_type = "monthly"')
        with self.assertRaisesRegex(MODULE.ValidationError, "schedule_type"):
            MODULE.validate_repository(self.write_repo(config, {"job.md": invalid_job}))
        for labels in ("[]", '[" "]', '["a", "a"]'):
            with self.assertRaises(MODULE.ValidationError):
                MODULE.validate_repository(self.write_repo(config.replace('base_labels = ["task"]', f"base_labels = {labels}"), {"job.md": MODULE.example_job("job")}))
        job = MODULE.example_job("job").replace('timezone = "Asia/Tokyo"', 'timezone = "Asia/Tokyo"\nlabels = ["job-label"]')
        result = MODULE.validate_repository(self.write_repo(config, {"job.md": job}))
        self.assertEqual(result["jobs"][0]["preflight_labels"], ["task", "Severity: High", "Severity: Medium", "Severity: Low", "priority/P1", "priority/P2", "priority/P3", "job-label"])

    def test_validator_schedule_and_text_boundaries(self) -> None:
        config = MODULE.EXAMPLE_CONFIG
        daily_with_empty = MODULE.example_job("daily").replace('schedule_type = "weekly"\nweekdays = ["monday"]', 'schedule_type = "daily"\nweekdays = []')
        with self.assertRaises(MODULE.ValidationError):
            MODULE.validate_repository(self.write_repo(config, {"job.md": daily_with_empty}))
        duplicate_days = MODULE.example_job("weekly").replace('["monday"]', '["monday", "monday"]')
        with self.assertRaises(MODULE.ValidationError):
            MODULE.validate_repository(self.write_repo(config, {"job.md": duplicate_days}))
        for text in ("# ", "# Name"):
            body = text + MODULE.example_job("job")[len("# Example"):]
            if text == "# Name":
                body = body.replace("Inspect the repository.", "   ")
            with self.assertRaises(MODULE.ValidationError):
                MODULE.validate_repository(self.write_repo(config, {"job.md": body}))


if __name__ == "__main__":
    unittest.main()
