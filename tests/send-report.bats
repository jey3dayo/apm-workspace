#!/usr/bin/env bats
#
# send-report.sh が報告 keyword に task_id を強制することを検証する。
#
# WORKER.md は全報告に task_id を載せる契約だが、実運用で Codex Luna が payload の
# exact 指示を破って bare `READY` を送った（CyMaster PR #892 のフィールド報告）。
# orchestrator は task_id で照合するため、欠けた報告は「どの task か分からないもの」
# になり、無応答と区別できない。生成側の遵守に任せず transport の入口で止める。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/skills/agmsg-delegation/scripts/send-report.sh"
  # 実際の agmsg へ送らせない。通過したら引数がそのまま echo される。
  export AGMSG_SEND_SCRIPT=/bin/echo
}

@test "a bare keyword without a task_id is refused" {
  for kw in READY WORKING BLOCKED DONE REVIEW; do
    run bash -c "printf '%s\n' '$kw' | '$SCRIPT' apm worker orch"
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing its task_id"* ]]
  done
}

@test "a keyword with a task_id passes through" {
  run bash -c "printf 'REVIEW task-42\nverdict: approve\n' | '$SCRIPT' apm worker orch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REVIEW task-42"* ]]
}

# delimiter 境界を全 keyword で確認する。`[[:space:]]*` だった間は `READYtask-42` と
# `REVIEW: approve` が通過し、orchestrator が待つ exact `<KEYWORD> <task_id>` にならない
# まま送信された（reviewer-field-fixes の実測）。
@test "delimiter boundaries are enforced for every report keyword" {
  for kw in READY WORKING BLOCKED DONE REVIEW; do
    # 区切りなし
    run bash -c "printf '%stask-42\n' '$kw' | '$SCRIPT' apm worker orch"
    [ "$status" -eq 2 ]
    # colon 直結
    run bash -c "printf '%s: approve\n' '$kw' | '$SCRIPT' apm worker orch"
    [ "$status" -eq 2 ]
    # 空白のみ
    run bash -c "printf '%s   \n' '$kw' | '$SCRIPT' apm worker orch"
    [ "$status" -eq 2 ]
    # space 区切りは通る
    run bash -c "printf '%s task-1\n' '$kw' | '$SCRIPT' apm worker orch"
    [ "$status" -eq 0 ]
    # tab 区切りも通る
    run bash -c "printf '%s\ttask-2\n' '$kw' | '$SCRIPT' apm worker orch"
    [ "$status" -eq 0 ]
  done
}

@test "a body that does not start with a report keyword is left alone" {
  # handoff 本文など、keyword で始まらない報告は従来どおり通す。
  run bash -c "printf 'source_role: Steward\ntarget_role: Architect\n' | '$SCRIPT' apm worker orch"
  [ "$status" -eq 0 ]
}

@test "an empty body is still refused" {
  run bash -c "printf '' | '$SCRIPT' apm worker orch"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must not be empty"* ]]
}
