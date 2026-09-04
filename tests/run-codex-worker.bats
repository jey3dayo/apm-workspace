#!/usr/bin/env bats
#
# run-codex-worker.sh の role/model allowlist を検証する。
#
# この allowlist が無かった間、script は role だけを検証して $3 をそのまま
# `codex -m` へ渡していた。orchestrator-worker の tier 表に「implement は luna、
# review は sol 既定」と書いても、runtime は implement=sol も review=luna も
# 拒否しなかった（reviewer-sol の design-audit medium 指摘）。
#
# 正本は orchestrator-worker の tier 表で、script はその写しである。写しは黙って
# ずれるので、下の drift テストが表と script の両方から model ID を機械的に
# 取り出して突き合わせる。表の行が書き換わったらここが落ちる。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/skills/agmsg-delegation/scripts/run-codex-worker.sh"
  SKILL="$REPO_ROOT/catalog/skills/orchestrator-worker/SKILL.md"
  PROJECT="$(mktemp -d)"
  PAYLOAD="$(mktemp)"
  printf 'noop\n' >"$PAYLOAD"
  # codex 本体を起動させない。allowlist は引数検証なので、実行前に exit する。
  export AGMSG_CODEX_BIN="$REPO_ROOT/tests/does-not-exist-codex"
}

teardown() {
  rm -rf -- "$PROJECT" "$PAYLOAD"
}

# script が role ごとに許可している model を取り出す
script_models_for() {
  sed -n "s/^$1) allowed_models=(\(.*\)) ;;$/\1/p" "$SCRIPT"
}

# tier 表の行から model ID を取り出す（表記は \`gpt-5.6-*\` で統一されている前提）
skill_models_for() {
  grep -E "^\| $1 " "$SKILL" | grep -oE 'gpt-5\.6-[a-z]+' | sort -u | tr '\n' ' '
}

@test "implement rejects a reviewer-tier model" {
  run "$SCRIPT" implement "$PROJECT" gpt-5.6-sol "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed for role implement"* ]]
}

@test "review rejects a worker-tier model" {
  run "$SCRIPT" review "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed for role review"* ]]
}

@test "an unknown model is rejected for both roles" {
  for role in implement review; do
    run "$SCRIPT" "$role" "$PROJECT" gpt-9-nonexistent "$PAYLOAD"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not allowed for role $role"* ]]
  done
}

@test "allowed models pass the allowlist and fail later, not at validation" {
  # 許可された組合せは allowlist を通過し、存在しない codex 本体で落ちる。
  # exit 2 (引数検証) ではないことが「通過した」ことの証拠になる。
  run "$SCRIPT" implement "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -ne 2 ]
  [[ "$output" != *"not allowed for role"* ]]
}

@test "script allowlist matches the orchestrator-worker tier table" {
  local script_impl skill_impl script_review skill_review
  script_impl="$(script_models_for implement | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  skill_impl="$(skill_models_for Worker)"
  [ "$script_impl" = "$skill_impl" ] || {
    printf 'implement drift:\n  script: %s\n  skill : %s\n' "$script_impl" "$skill_impl" >&2
    return 1
  }

  script_review="$(script_models_for review | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  skill_review="$(skill_models_for Reviewer)"
  [ "$script_review" = "$skill_review" ] || {
    printf 'review drift:\n  script: %s\n  skill : %s\n' "$script_review" "$skill_review" >&2
    return 1
  }
}
