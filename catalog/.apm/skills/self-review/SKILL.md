---
name: self-review
description: >-
  「PR作ったから見て」「マージ前にレビュー」「セルフレビュー」と依頼されたときに、
  既存PRの独立レビューを行う。post-PR専用で、shipの出荷前検証や
  pr-followupのコメント対応とは別。
---

# Self-review

Run after the PR exists and before `pr-followup` handles comments. This skill owns its tiers and two-NG limit for post-PR review only; `ship`'s pre-PR gates remain separate. Add no pre-PR or sandbox-measurement prerequisites.

## Snapshot and classify

1. Read the PR number, base/head branch names, and full `baseRefOid` / `headRefOid` with `gh pr view --json number,baseRefName,headRefName,baseRefOid,headRefOid`. Record both full SHAs.
2. Confirm the checked-out `HEAD` is the PR head SHA and the changed paths have no local edits. Get the exact PR patch with `gh pr diff <number>`. For counts, make the two commits available locally and run both `git diff -M --numstat <base-sha>...<head-sha>` and `git diff -M --name-status <base-sha>...<head-sha>`; do not substitute branch names or stale tracking refs. Re-read both remote SHAs after capturing the patch. If either moved, restart with the latest snapshot. Do not launch a reviewer against a different or locally modified version of an affected file.
3. From `--name-status`, count `F` as changed paths; count both old and new paths for a rename. From `--numstat`, set `L` to all numeric additions plus deletions. A binary `-` count, gitlink, unreadable file, or path whose purpose cannot be classified is unknown and therefore heavy.
4. Assign the highest applicable tier, in this order:

   - **Heavy:** `F >= 10`, `L >= 500`, any file deletion (`D` status in `--name-status`), binary/gitlink/unknown content, or any distribution, sync, deploy, permission, auth, credential, secret, security-boundary, workflow-permission, or shared-agent-instruction path. Treat `.env*`, credential/secret/password files, auth/authorization/permission/security directories, `.github/workflows/**`, deployment/sync scripts and config, and `catalog/.apm/instructions/**` as heavy. Deleted lines count toward `L` but do not independently make a change heavy. A rename counts both paths.
   - Light: after excluding every heavy condition, either `F <= 3` and `L <= 100` with only docs, version metadata, or lock metadata; or `F = 1` and `L <= 10` with a known, non-risky text path. Including lock metadata here is intentional.
   - Ordinary: everything else. A skill `SKILL.md` is agent behavior and is ordinary at minimum. If classification is ambiguous, move up one tier.

Treat a version change as version-only only after comparing parsed base and head metadata with the version field removed and confirming all remaining fields are equal. In particular, any `package.json` script or other field change disqualifies it from version-only. A risk path stays heavy regardless of size or filename.

## Choose the reviewer

Identify the current provider from the active session identity and its process-specific marker (for example, `CLAUDECODE` or `CODEX_THREAD_ID`); an installed binary alone does not identify the caller. If the active provider is unclear from the session and environment, ask the user which runtime is active.

Use a fresh, standalone session in the opposite provider. For Codex, use [orchestrator-worker's Reviewer tier](../orchestrator-worker/SKILL.md) to select standard or upper difficulty and resolve the current model ID in its [model reference](../orchestrator-worker/references/models.md). Consult the model reference when updating Codex model choices. Use only that model-selection guidance; this skill's review procedure is self-contained. Select the standard tier at medium reasoning for ordinary work and the upper difficulty tier at high reasoning for heavy work. For this skill, use Claude `sonnet` at medium effort for ordinary work and `opus` at high effort for heavy work, regardless of general Reviewer defaults. This skill's reviewer selection is an explicit exception to orchestrator-worker §1's Reviewer allowlist validation; do not return `BLOCKED` solely because a reviewer selected here is outside that allowlist. Do not copy versioned model IDs into this skill.

If the opposite CLI, its authentication, or its selected model is unavailable, try a fresh standalone session in the current provider at the same tier. Report the fallback provider, model, and reason. A failed or unavailable review is `BLOCKED`, never `OK` or `NG`; if both providers fail, stop and report the blocker. A fallback does not reset the NG count.

Before launching either reviewer command, resolve that provider's CLI and confirm its version and every flag used in the command against that CLI's `--version` and `--help` output.

Pass the captured patch and both SHAs in the review prompt. Instruct the reviewer to report only concrete correctness, security, compatibility, or data-loss findings, and explicitly forbid suggestions to add tests or checks, cosmetic edits, or unrelated improvements. Require this output shape:

```text
VERDICT: OK|NG
FINDINGS:
- [severity] path:line — concrete consequence
```

List at most three findings. Return `VERDICT: NG` when at least one actionable defect is found; otherwise return `VERDICT: OK` and no findings. The reviewer must not edit files, run write-capable tools, or perform external writes.

### Codex reviewer

From a Claude session, send the prompt on stdin to a fresh Codex exec. The read-only setup is:

```sh
printf '%s\n' "$REVIEW_PROMPT" | codex exec --ephemeral --ignore-user-config --ignore-rules \
  --disable hooks --disable plugins --disable apps -c 'mcp_servers={}' \
  -s read-only -m "$MODEL" -c "model_reasoning_effort=$EFFORT" \
  -C "$REPO" -
```

### Claude reviewer

From a Codex session, pass the prompt on stdin. The restricted tool allowlist gives the reviewer file-reading tools only:

```sh
printf '%s\n' "$REVIEW_PROMPT" | claude -p --model "$MODEL" --effort "$EFFORT" \
  --restricted --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
  --tools 'Read,Glob,Grep' --disallowedTools 'Bash,Edit,Write,NotebookEdit,Agent' \
  --permission-mode dontAsk --setting-sources '' --settings '{"disableAllHooks":true}' \
  --disable-slash-commands --no-session-persistence
```

These commands provide the snapshot diff as prompt input. Before launch, verify the working tree's affected paths match the recorded PR head; afterward, re-read the PR SHAs. If either SHA changed, discard the verdict and review the full latest PR diff. The Claude reviewer cannot run Git, so do not ask it to fetch, compare SHAs, or calculate checksums.

## Handle the result

- Light: skip model review and report `SKIPPED (light)`, the thresholds, and whether required checks for the current head are green. Do not label a skipped review `VERDICT: OK`. If a merge was explicitly requested, escalate to ordinary review first.
- Ordinary or heavy: on `OK`, confirm the PR still has the recorded base/head SHAs. On `NG`, the original author fixes the findings, captures the new full PR diff, and reruns the same tier. Stop after the second `NG` and ask the user to decide. A blocked or malformed review is not a verdict and cannot satisfy a merge gate.
- CI: for the latest commit, require zero failed checks, including both required and optional checks. Every reported check must apply to that commit and be successful; missing or pending required checks are not green.
- Merge: merge only when the user explicitly requested it, the latest applicable review has a real `VERDICT: OK`, and latest-commit CI is green under the CI rule above (zero failed checks, required or optional). Never merge after `SKIPPED`, `BLOCKED`, `NG`, or a stale verdict. Exception: when a project's role settings grant standing permission, a PR whose Opus or Sol review is approved with 0 blocking findings, whose CI is green and whose merge state is CLEAN may be merged by the assigned dev agent without asking each time, never with `--admin`; deploys and production releases still need the user's explicit OK.

Report the PR snapshot SHAs, tier and model, verdict or skip/block reason, findings or correction count, and current-head CI state. Keep review outcome, CI state, and any requested merge as separate observed results.
