#!/usr/bin/env bats
#
# run-opencode-worker.sh の role/model allowlist と sandbox write allowlist を
# 検証する。opencode は Worker 専用 (implement only) で、tier 表 Worker 行の
# opencode 列と script の allowlist が食い違うと runtime が黙って別 model を
# 通してしまう。正本は orchestrator-worker の tier 表で、script はその写しである。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/skills/agmsg-delegation/scripts/run-opencode-worker.sh"
  SKILL="$REPO_ROOT/catalog/skills/orchestrator-worker/SKILL.md"
  PROJECT="$(mktemp -d)"
  PAYLOAD="$(mktemp)"
  printf 'noop\n' >"$PAYLOAD"
  # opencode 本体を起動させない。allowlist は引数検証なので、実行前に exit する。
  export AGMSG_OPENCODE_BIN="$REPO_ROOT/tests/does-not-exist-opencode"
}

teardown() {
  rm -rf -- "$PROJECT" "$PAYLOAD"
}

# tier 表の Worker 行から opencode の model ID を取り出す
# (実在する id は `deepseek/deepseek-v4-flash` のみ)
skill_opencode_models() {
  grep -E '^\| Worker ' "$SKILL" | grep -oE 'deepseek/[a-z0-9.-]+' | sort -u | tr '\n' ' '
}

@test "implement with the allowed model passes the allowlist and fails later, not at validation" {
  # 許可された組合せは allowlist を通過し、存在しない opencode 本体で落ちる。
  # exit 2 (引数検証) ではないことが「通過した」ことの証拠になる。
  run "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -ne 2 ]
  [[ "$output" != *"not allowed for role"* ]]
}

@test "an allowed-outside model is rejected for implement" {
  run "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-pro "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed for role implement"* ]]
}

@test "an unknown model is rejected" {
  run "$SCRIPT" implement "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed for role implement"* ]]
}

@test "review role is rejected; opencode cannot be a reviewer" {
  run "$SCRIPT" review "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -eq 2 ]
}

@test "an unsupported role other than review is also rejected" {
  run "$SCRIPT" plan "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -eq 2 ]
}

@test "AGMSG_OPENCODE_VARIANT accepts low, high, and max" {
  for variant in low high max; do
    run env AGMSG_OPENCODE_VARIANT="$variant" AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY=1 \
      "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
    [ "$status" -eq 0 ]
  done
}

@test "an unsupported AGMSG_OPENCODE_VARIANT is rejected" {
  run env AGMSG_OPENCODE_VARIANT=medium \
    "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"AGMSG_OPENCODE_VARIANT"* ]]
}

@test "script allowlist matches the orchestrator-worker tier table" {
  local script_models skill_models
  script_models="$(sed -n 's/^allowed_models=(\(.*\))$/\1/p' "$SCRIPT" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  skill_models="$(skill_opencode_models)"
  [ "$script_models" = "$skill_models" ] || {
    printf 'opencode allowlist drift:\n  script: %s\n  skill : %s\n' "$script_models" "$skill_models" >&2
    return 1
  }
}

# 以下は sandbox write allowlist の回帰テスト。~/.local/share/opencode は
# auth.json の所在で、実測で write 拒否を確認済み。ここへ書けてしまうと worker が
# 他 provider (Z.AI / opencode zen) の credential まで書き換えられる。
#
# AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY=1 は profile 生成だけをテストするための
# 専用モードで、opencode 本体・sandbox-exec・DeepSeek credential のいずれも
# 要求せず、write allowlist の内容を直接検証できる。

@test "the sandbox profile excludes ~/.local/share/opencode (the auth.json location)" {
  run env AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY=1 \
    "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" != *".local/share/opencode"* ]]
}

@test "the sandbox profile allows /dev, tmp, runtime_dir, agmsg state, and the project" {
  run env AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY=1 \
    "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'(subpath "/dev")'* ]]
  [[ "$output" == *"agmsg"* ]]
  [[ "$output" == *"$(cd "$PROJECT" && pwd -P)"* ]]
}

@test "AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY does not require opencode or sandbox-exec" {
  run env AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY=1 AGMSG_OPENCODE_BIN=/no/such/opencode \
    "$SCRIPT" implement "$PROJECT" deepseek/deepseek-v4-flash "$PAYLOAD"
  [ "$status" -eq 0 ]
}
