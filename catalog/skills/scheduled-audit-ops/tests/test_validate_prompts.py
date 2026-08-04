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

HELPER_PATH = SCRIPT.parent / "audit_contracts.py"
HELPER_SPEC = importlib.util.spec_from_file_location("audit_contracts", HELPER_PATH)
assert HELPER_SPEC and HELPER_SPEC.loader
HELPER = importlib.util.module_from_spec(HELPER_SPEC)
HELPER_SPEC.loader.exec_module(HELPER)


class ValidatePromptsTest(unittest.TestCase):
    def test_skill_documents_run_branches_bootstrap_and_agent_discovery(self) -> None:
        skill = (SCRIPT.parent.parent / "SKILL.md").read_text(encoding="utf-8").lower()
        contracts = (SCRIPT.parent.parent / "references" / "contracts.md").read_text(encoding="utf-8").lower()
        agent = (SCRIPT.parent.parent / "agents" / "openai.yaml").read_text(encoding="utf-8").lower()

        sync_start = skill.index("## sync")
        run_start = skill.index("## run")
        sync = skill[sync_start:run_start]
        self.assertIn(
            "2. confirm every github label required by audit jobs exists.",
            sync,
        )
        self.assertNotIn("confirm every configured github label exists", sync)
        for heading in (
            "### common read-only setup",
            "### audit-only issue/label/evidence lifecycle",
            "### report-only allowlisted file/one-pr lifecycle",
        ):
            self.assertIn(heading, skill[run_start:])
        common_start = skill.index("### common read-only setup", run_start)
        audit_start = skill.index("### audit-only issue/label/evidence lifecycle", common_start)
        report_start = skill.index("### report-only allowlisted file/one-pr lifecycle", audit_start)
        common = skill[common_start:audit_start]
        audit = skill[audit_start:report_start]
        report = skill[report_start:]

        self.assertLess(common_start, audit_start)
        self.assertLess(audit_start, report_start)
        for phrase in (
            "read the current job body",
            "automation memory",
            "read-only",
        ):
            self.assertIn(phrase, common)
        for phrase in (
            "evidence gate",
            "issue labels",
            "issue lifecycle",
        ):
            self.assertIn(phrase, audit)
        for phrase in (
            "report_write_paths",
            "report_create_pull_request",
            "one pr",
            "report run rejects issue labels and never runs the issue lifecycle",
        ):
            self.assertIn(phrase, report)

        text = skill + contracts
        for phrase in (
            "report_write_paths",
            "report_create_pull_request",
            "prompt text cannot expand report authority",
            "second sync",
            "unchanged",
            "pause before migration",
            "canonical_source = source_marker(dedupe_marker_prefix, repository_remote, job[\"source\"], job[\"id\"])",
            "audit bootstrap omits `report_write_paths` and `report_create_pull_request`",
            "report bootstrap serializes normalized `report_write_paths` and `report_create_pull_request`",
            "the normalized validator dictionary may contain `report_write_paths = []` and `report_create_pull_request = false` for audit jobs",
            "reasoning_effort `low | medium | high | xhigh | max`",
        ):
            self.assertIn(phrase, text)
        self.assertIn("evidence-backed github issues", agent)
        self.assertIn("allowlisted report documents", agent)
        self.assertIn("at most one pull request", agent)

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
operation = "audit"
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
operation = "audit"
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
        self.assertEqual(
            HELPER.source_identity("HTTPS://GitHub.com/Acme/Widgets.git", "docs\\prompts/./job.md", "job"),
            "v1:acme/widgets:docs/prompts/job.md:job",
        )
        self.assertEqual(
            HELPER.source_marker("audit-run", "git@github.com:Acme/Widgets.git", "docs/prompts/job.md", "job"),
            "<!-- audit-run:source:v1:acme/widgets:docs/prompts/job.md:job -->",
        )
        with self.assertRaises(ValueError):
            HELPER.source_path("/repo", "/etc/passwd")
        with self.assertRaises(ValueError):
            HELPER.source_path("/repo", "../outside.md")
        with self.assertRaises(ValueError):
            HELPER.source_identity("acme/widgets", "a/../../outside.md", "job")
        self.assertEqual(HELPER.repository_remote_slug("https://github.com/acme/widgets.git"), "acme/widgets")
        self.assertEqual(HELPER.repository_remote_slug("git@github.com:acme/widgets.git"), "acme/widgets")
        first = HELPER.finding_fingerprint("job", "security", "owner", "behavior")
        self.assertEqual(first, "93601981a8a40fc5ec5adcbc538acab44de333b126eba76bfdbbc3ba2ea0d4f1")
        self.assertEqual(list(inspect.signature(HELPER.finding_fingerprint).parameters), ["job_id", "category", "stable_owner", "behavior_key"])
        self.assertEqual(HELPER.issue_marker("audit-run", "job", first), f"<!-- audit-run:job:{first} -->")
        self.assertEqual(first, HELPER.finding_fingerprint("job", "security", "owner", "behavior"))
        self.assertNotEqual(first, HELPER.finding_fingerprint("job", "security", "other", "behavior"))
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=False, issue_state=None, evidence_sufficient=False), "hold")
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=True, issue_state="rejected", evidence_sufficient=True), "suppress")
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=False, issue_state="open", evidence_sufficient=True), "close")
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=True, issue_state=None, evidence_sufficient=True), "create")
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=True, issue_state="closed", evidence_sufficient=True), "reopen")
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=True, issue_state="open", evidence_sufficient=True, changed=True), "update")
        self.assertEqual(HELPER.lifecycle_disposition(finding_present=True, issue_state="open", evidence_sufficient=True, changed=False), "unchanged")
        with self.assertRaises(ValueError):
            HELPER.lifecycle_disposition(finding_present=False, issue_state="closed", evidence_sufficient=True)
        with self.assertRaises(ValueError):
            HELPER.lifecycle_disposition(finding_present=True, issue_state="open", evidence_sufficient=False, changed=True)
        records = [HELPER.IssueRecord(9, "z-source"), HELPER.IssueRecord(3, "b-source"), HELPER.IssueRecord(3, "a-source")]
        result = HELPER.reconcile_issues(records)
        self.assertEqual(result.canonical.number, 3)
        self.assertEqual(result.duplicate_numbers, (9,))
        self.assertEqual(HELPER.preferred_source_writer(["z-source", "a-source"]), "a-source")
        self.assertIsNone(HELPER.reconcile_issues([]).canonical)
        self.assertFalse(hasattr(HELPER, "reconcile_duplicates"))
        self.assertFalse(hasattr(HELPER, "single_writer_winner"))
        with self.assertRaises(ValueError):
            HELPER.reconcile_issues([HELPER.IssueRecord(0, "source")])
        self.assertEqual(
            HELPER.schedule_rrule("weekly", ["monday"], "10:00", interval=2),
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO;BYHOUR=10;BYMINUTE=0",
        )
        self.assertEqual(
            HELPER.schedule_rrule(
                "monthly", ["monday"], "10:00", week_of_month=1
            ),
            "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1;BYHOUR=10;BYMINUTE=0",
        )

    def test_normalizes_biweekly_audit_and_monthly_report(self) -> None:
        audit = MODULE.example_job("security-audit").replace(
            'enabled = true\noperation = "audit"\nschedule_type = "weekly"',
            'enabled = true\noperation = "audit"\nschedule_type = "weekly"\ninterval = 2',
        ).replace(
            'timezone = "Asia/Tokyo"',
            'timezone = "Asia/Tokyo"\nreasoning_effort = "xhigh"\nlabels = ["area/security"]',
        )
        report = MODULE.example_job("ai-kpi-monthly-review").replace(
            'enabled = true\noperation = "audit"\nschedule_type = "weekly"\nweekdays = ["monday"]',
            'enabled = true\noperation = "report"\nschedule_type = "monthly"\nweekdays = ["monday"]\nweek_of_month = 1',
        ).replace(
            'timezone = "Asia/Tokyo"',
            'timezone = "Asia/Tokyo"\nreasoning_effort = "high"\nreport_write_paths = ["docs/ai-kpi.md"]\nreport_create_pull_request = true',
        )
        root = self.write_repo(
            MODULE.EXAMPLE_CONFIG,
            {"security.md": audit, "ai-kpi.md": report},
        )

        result = {job["id"]: job for job in MODULE.validate_repository(root)["jobs"]}

        self.assertEqual(result["security-audit"]["operation"], "audit")
        self.assertEqual(result["security-audit"]["interval"], 2)
        self.assertEqual(result["security-audit"]["reasoning_effort"], "xhigh")
        self.assertEqual(
            result["security-audit"]["rrule"],
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO;BYHOUR=10;BYMINUTE=0",
        )
        self.assertEqual(
            result["ai-kpi-monthly-review"]["report_write_paths"],
            ["docs/ai-kpi.md"],
        )
        self.assertTrue(result["ai-kpi-monthly-review"]["report_create_pull_request"])
        self.assertEqual(
            result["ai-kpi-monthly-review"]["rrule"],
            "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1;BYHOUR=10;BYMINUTE=0",
        )

    def test_rejects_invalid_schedule_and_operation_combinations(self) -> None:
        base = MODULE.example_job("job")
        cases = {
            "interval": base.replace('schedule_type = "weekly"', 'schedule_type = "weekly"\ninterval = 0'),
            "week_of_month": base.replace('schedule_type = "weekly"', 'schedule_type = "monthly"'),
            "weekdays": base.replace(
                'schedule_type = "weekly"\nweekdays = ["monday"]',
                'schedule_type = "monthly"\nweekdays = ["monday", "tuesday"]\nweek_of_month = 1',
            ),
            "daily": base.replace(
                'schedule_type = "weekly"\nweekdays = ["monday"]',
                'schedule_type = "daily"\nweek_of_month = 1',
            ),
            "reasoning_effort": base.replace(
                'timezone = "Asia/Tokyo"',
                'timezone = "Asia/Tokyo"\nreasoning_effort = "ultra"',
            ),
            "report_write_paths": base.replace(
                'timezone = "Asia/Tokyo"',
                'timezone = "Asia/Tokyo"\nreport_write_paths = ["docs/result.md"]',
            ),
            "labels": base.replace(
                'operation = "audit"',
                'operation = "report"\nlabels = ["area/security"]',
            ),
        }
        for expected_field, job in cases.items():
            with self.subTest(expected_field=expected_field):
                with self.assertRaisesRegex(MODULE.ValidationError, expected_field):
                    MODULE.validate_repository(
                        self.write_repo(MODULE.EXAMPLE_CONFIG, {"job.md": job})
                    )

    def test_report_paths_are_repository_relative_and_symlink_safe(self) -> None:
        report = MODULE.example_job("report").replace('operation = "audit"', 'operation = "report"').replace(
            'timezone = "Asia/Tokyo"',
            'timezone = "Asia/Tokyo"\nreport_write_paths = ["docs/result.md"]\nreport_create_pull_request = true',
        )
        root = self.write_repo(MODULE.EXAMPLE_CONFIG, {"report.md": report})
        (root / "docs" / "result.md").write_text("result\n", encoding="utf-8")
        self.assertEqual(
            MODULE.validate_repository(root)["jobs"][0]["report_write_paths"],
            ["docs/result.md"],
        )

        escaped = report.replace('docs/result.md', '../outside.md')
        with self.assertRaisesRegex(MODULE.ValidationError, "report_write_paths"):
            MODULE.validate_repository(
                self.write_repo(MODULE.EXAMPLE_CONFIG, {"report.md": escaped})
            )

        outside = root.parent / f"{root.name}-outside.md"
        outside.write_text("outside\n", encoding="utf-8")
        (root / "docs" / "link.md").symlink_to(outside)
        linked = report.replace('docs/result.md', 'docs/link.md')
        (root / "docs" / "prompts" / "report.md").write_text(linked, encoding="utf-8")
        with self.assertRaisesRegex(MODULE.ValidationError, "report_write_paths"):
            MODULE.validate_repository(root)

    def test_rejects_boolean_schedule_integers(self) -> None:
        cases = {
            "interval": MODULE.example_job("boolean-interval").replace(
                'schedule_type = "weekly"',
                'schedule_type = "weekly"\ninterval = true',
            ),
            "week_of_month": MODULE.example_job("boolean-week-of-month").replace(
                'schedule_type = "weekly"',
                'schedule_type = "monthly"\nweek_of_month = false',
            ),
        }
        for expected_field, job in cases.items():
            with self.subTest(expected_field=expected_field):
                with self.assertRaisesRegex(MODULE.ValidationError, expected_field):
                    MODULE.validate_repository(
                        self.write_repo(MODULE.EXAMPLE_CONFIG, {"job.md": job})
                    )

    def test_rejects_explicit_interval_on_monthly_jobs(self) -> None:
        for interval in (1, 2):
            with self.subTest(interval=interval):
                job = MODULE.example_job("monthly").replace(
                    'schedule_type = "weekly"',
                    f'schedule_type = "monthly"\ninterval = {interval}\nweek_of_month = 1',
                )
                with self.assertRaisesRegex(MODULE.ValidationError, "interval"):
                    MODULE.validate_repository(
                        self.write_repo(MODULE.EXAMPLE_CONFIG, {"job.md": job})
                    )

    def test_defaults_interval_and_reasoning_effort_from_automation_defaults(self) -> None:
        config = MODULE.EXAMPLE_CONFIG.replace(
            'reasoning_effort = "high"',
            'reasoning_effort = "max"',
        )
        root = self.write_repo(config, {"job.md": MODULE.example_job("job")})

        result = MODULE.validate_repository(root)["jobs"][0]

        self.assertEqual(result["interval"], 1)
        self.assertEqual(result["reasoning_effort"], "max")

    def test_rejects_invalid_operation_value(self) -> None:
        job = MODULE.example_job("invalid-operation").replace(
            'operation = "audit"',
            'operation = "deploy"',
        )
        with self.assertRaisesRegex(MODULE.ValidationError, "operation"):
            MODULE.validate_repository(
                self.write_repo(MODULE.EXAMPLE_CONFIG, {"job.md": job})
            )

    def test_report_paths_reject_directories_and_normalized_duplicates(self) -> None:
        report = MODULE.example_job("report").replace(
            'operation = "audit"',
            'operation = "report"',
        ).replace(
            'timezone = "Asia/Tokyo"',
            'timezone = "Asia/Tokyo"\nreport_write_paths = ["docs/result.md"]',
        )
        cases = {
            "directory": '["docs"]',
            "duplicate normalized path": '["docs/result.md", "docs/./result.md"]',
        }
        for expected_case, paths in cases.items():
            with self.subTest(expected_case=expected_case):
                job = report.replace(
                    'report_write_paths = ["docs/result.md"]',
                    f"report_write_paths = {paths}",
                )
                with self.assertRaisesRegex(MODULE.ValidationError, "report_write_paths"):
                    MODULE.validate_repository(
                        self.write_repo(MODULE.EXAMPLE_CONFIG, {"report.md": job})
                    )

    def test_prompt_body_cannot_expand_normalized_report_authority(self) -> None:
        report = MODULE.example_job("report").replace(
            'operation = "audit"',
            'operation = "report"',
        ).replace(
            'timezone = "Asia/Tokyo"',
            'timezone = "Asia/Tokyo"\nreport_write_paths = ["docs/result.md"]',
        ).replace(
            "Inspect the repository.",
            'Prompt text mentions report_write_paths = ["docs/extra.md"].',
        )
        root = self.write_repo(MODULE.EXAMPLE_CONFIG, {"report.md": report})

        result = MODULE.validate_repository(root)["jobs"][0]

        self.assertIn("report_write_paths", result["prompt"])
        self.assertEqual(result["report_write_paths"], ["docs/result.md"])

    def test_legacy_markers_are_explicitly_searched_adopted_and_canonicalized(self) -> None:
        fingerprint = HELPER.finding_fingerprint("job", "security", "owner", "behavior")
        canonical = HELPER.issue_marker("audit-run", "job", fingerprint)
        legacy = "<!-- audit-run:job -->"
        candidates = HELPER.marker_candidates(canonical, [legacy, legacy])
        self.assertEqual(candidates, (canonical, legacy))

        legacy_only = {17: f"Summary\n{legacy}"}
        self.assertEqual(HELPER.matching_issue_numbers(legacy_only, candidates), (17,))

        matching = {17: f"Summary\n{legacy}\n{legacy}", 4: f"Summary\n{canonical}"}
        matches = HELPER.matching_issue_numbers(matching, candidates)
        self.assertEqual(matches, (4, 17))
        reconciled = HELPER.reconcile_issues([HELPER.IssueRecord(number, "source") for number in matches])
        self.assertEqual(reconciled.canonical.number, 4)
        self.assertEqual(reconciled.duplicate_numbers, (17,))
        updated = HELPER.migrate_issue_body(matching[4], canonical, candidates)
        self.assertEqual(updated.count(canonical), 1)
        self.assertNotIn(legacy, updated)

    def test_lifecycle_rejects_full_contradictory_input_matrix(self) -> None:
        invalid_cases = [
            (False, None, False, True),
            (False, "open", False, True),
            (False, "open", True, True),
            (False, "closed", False, False),
            (False, "closed", True, False),
            (False, "rejected", False, False),
            (False, "rejected", True, False),
            (True, None, False, True),
            (True, None, True, True),
            (True, "rejected", True, True),
            (True, "open", False, True),
            (True, "closed", False, True),
            (True, "rejected", False, True),
        ]
        for finding_present, issue_state, evidence_sufficient, changed in invalid_cases:
            with self.subTest(finding_present=finding_present, issue_state=issue_state, evidence_sufficient=evidence_sufficient, changed=changed):
                with self.assertRaises(ValueError):
                    HELPER.lifecycle_disposition(
                        finding_present=finding_present,
                        issue_state=issue_state,
                        evidence_sufficient=evidence_sufficient,
                        changed=changed,
                    )
        for invalid_kwargs in (
            {"finding_present": True, "issue_state": "pending", "evidence_sufficient": True, "changed": False},
            {"finding_present": 1, "issue_state": None, "evidence_sufficient": True, "changed": False},
            {"finding_present": True, "issue_state": None, "evidence_sufficient": 1, "changed": False},
            {"finding_present": True, "issue_state": None, "evidence_sufficient": True, "changed": 0},
        ):
            with self.assertRaises(ValueError):
                HELPER.lifecycle_disposition(**invalid_kwargs)

    def test_validator_source_is_repository_relative_and_works_with_source_marker(self) -> None:
        root = self.write_repo(MODULE.EXAMPLE_CONFIG, {"job.md": MODULE.example_job("job")})
        result = MODULE.validate_repository(root)
        source = result["jobs"][0]["source"]
        self.assertEqual(source, "docs/prompts/job.md")
        self.assertEqual(
            HELPER.source_marker("scheduled-audit", "git@github.com:acme/widgets.git", source, "job"),
            "<!-- scheduled-audit:source:v1:acme/widgets:docs/prompts/job.md:job -->",
        )

    def test_validator_rejects_symlink_jobs_outside_docs_prompts_boundary(self) -> None:
        for target_name in ("outside.md", "docs/other.md"):
            with self.subTest(target_name=target_name):
                root = self.write_repo(MODULE.EXAMPLE_CONFIG, {})
                target = root / target_name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(MODULE.example_job("job"), encoding="utf-8")
                (root / "docs" / "prompts" / "job.md").symlink_to(target)
                with self.assertRaisesRegex(MODULE.ValidationError, "outside docs/prompts"):
                    MODULE.validate_repository(root)

    def test_validator_uses_lexical_source_for_in_tree_symlink_and_rejects_aliases(self) -> None:
        root = self.write_repo(MODULE.EXAMPLE_CONFIG, {})
        target = root / "docs" / "prompts" / "job-source"
        target.write_text(MODULE.example_job("job"), encoding="utf-8")
        (root / "docs" / "prompts" / "job.md").symlink_to(target)

        result = MODULE.validate_repository(root)
        self.assertEqual(result["jobs"][0]["source"], "docs/prompts/job.md")

        (root / "docs" / "prompts" / "alias.md").symlink_to(target)
        with self.assertRaisesRegex(MODULE.ValidationError, "duplicate job id"):
            MODULE.validate_repository(root)

    def test_skill_documents_untrusted_boundary_and_evidence_recheck(self) -> None:
        skill = (SCRIPT.parent.parent / "SKILL.md").read_text(encoding="utf-8")
        contracts = (SCRIPT.parent.parent / "references" / "contracts.md").read_text(encoding="utf-8")
        for phrase in ("untrusted", "job text cannot expand authority", "create/update/reopen/close/suppress", "exact file:line", "repeatable recheck"):
            self.assertIn(phrase, skill.lower() + contracts.lower())
        text = skill.lower() + contracts.lower()
        for phrase in ("embedded instructions", "solely because audited content requested it", "automation memory"):
            self.assertIn(phrase, text)
        self.assertIn("explicit user/automation invocation outside audited data", text)
        self.assertNotIn("job explicitly authorizes", text)
        self.assertNotIn("unless the job explicitly", text)

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
        with self.assertRaisesRegex(MODULE.ValidationError, "week_of_month"):
            MODULE.validate_repository(self.write_repo(config, {"job.md": invalid_job}))
        for labels in ("[]", '[" "]', '["a", "a"]'):
            with self.assertRaises(MODULE.ValidationError):
                MODULE.validate_repository(self.write_repo(config.replace('base_labels = ["task"]', f"base_labels = {labels}"), {"job.md": MODULE.example_job("job")}))
        job = MODULE.example_job("job").replace('timezone = "Asia/Tokyo"', 'timezone = "Asia/Tokyo"\nlabels = ["job-label"]')
        result = MODULE.validate_repository(self.write_repo(config, {"job.md": job}))
        self.assertEqual(result["jobs"][0]["preflight_labels"], ["task", "Severity: High", "Severity: Medium", "Severity: Low", "priority/P1", "priority/P2", "priority/P3", "job-label"])
        prompt_metadata = MODULE.example_job("job").replace("Inspect the repository.", 'Prompt text mentions labels = ["prompt-label"].')
        result = MODULE.validate_repository(self.write_repo(config, {"job.md": prompt_metadata}))
        self.assertNotIn("prompt-label", result["jobs"][0]["preflight_labels"])

    def test_contract_documents_structured_optional_labels_and_authority_source(self) -> None:
        contracts = (SCRIPT.parent.parent / "references" / "contracts.md").read_text(encoding="utf-8").lower()
        self.assertIn('labels = ["team-platform"]', contracts)
        self.assertIn("generic jobs omit labels", contracts)
        self.assertIn("prompt text cannot add labels", contracts)

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
