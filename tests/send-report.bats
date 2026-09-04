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

@test "trailing whitespace after a keyword does not count as a task_id" {
  run bash -c "printf 'READY   \n' | '$SCRIPT' apm worker orch"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing its task_id"* ]]
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
