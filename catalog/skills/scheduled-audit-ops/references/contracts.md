# Scheduled Audit Contracts

## Repository configuration

`docs/prompts/config.toml` is a versioned contract.

```toml
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
```

Resolve the repository name and Codex project ID from the local checkout and Codex project list. Do not commit clone paths or user-specific project IDs.

## Job file

Every job has an H1, a marked TOML block, and a Markdown prompt body. Use the H1 as the automation name. `id`, `enabled`, `schedule_type`, `time`, and `timezone` are required. A weekly job also requires `weekdays`. Keep `id` unique and stable within the repository.

````markdown
# Performance Audit

<!-- scheduled-audit-config -->

```toml
id = "performance-audit"
enabled = true
schedule_type = "weekly"
weekdays = ["monday"]
time = "09:00"
timezone = "Asia/Tokyo"
```

## Prompt

Inspect performance.
````

Keep category-specific audit targets and evidence rules in the prompt body. Keep notification policy, Issue labels, and common deduplication in this configuration and skill.

## Evidence gate

| Requirement    | Accepted evidence                                                                |
| -------------- | -------------------------------------------------------------------------------- |
| Current state  | file and line, test result, trace, query plan, runtime metric, CI timing, or log |
| Expected state | explicit repository contract or measurable target                                |
| Impact         | affected user, operation, resource, or scaling condition                         |
| Recheck        | the same command, query, trace, or metric can be repeated after a fix            |

Do not create an Issue unless every requirement passes. For an evidence-insufficient candidate, report it as held with only the next required measurement.

## Classification

| Label            | Rule                                                                                    |
| ---------------- | --------------------------------------------------------------------------------------- |
| Severity: High   | Security boundary, data loss, broad outage, or measured severe user impact              |
| Severity: Medium | Reproducible degradation, growing load, limited outage, or high-confidence scaling risk |
| Severity: Low    | Local inefficiency or small maintenance impact                                          |
| priority/P1      | Current release blocker or immediate operational incident                               |
| priority/P2      | Required before the next release, handoff, or explicit deadline                         |
| priority/P3      | Planned follow-up; default for an unmeasured Medium finding                             |

Record one severity rationale and one priority rationale in every Issue. Update the priority rationale with the measurement date when new measurements change priority.

## Issue contract

Use one Issue per finding. Include summary, evidence, impact, confidence, severity rationale, priority rationale, proposed fix, completion criteria, before measurement, and remeasurement method.

Embed exactly one marker:

<!-- scheduled-audit:<job-id>:<fingerprint> -->

Build the fingerprint from the job ID, category, stable owner, and behavior key. Exclude line numbers, commit SHAs, dates, and measured values.

## Lifecycle

| State                        | Required disposition                                                                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Open / update                | Append the latest evidence and measurement date to the matching open Issue.                                        |
| Closed / reopen              | Reopen a matching closed Issue only when the same problem recurs, and append regression evidence.                  |
| Resolved / close             | Recheck by the same method, append the result, and close the Issue when the finding is resolved.                   |
| Rejected / suppress          | Do not recreate an Issue that records a clear decision to reject the finding; report future matches as suppressed. |
| Evidence-insufficient / hold | Do not create an Issue; report the candidate with the next required measurement.                                   |
