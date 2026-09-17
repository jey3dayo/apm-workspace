#!/usr/bin/env bats
#
# run-cursor-worker.sh の role/model allowlist と sandbox write/read allowlist を
# 検証する。cursor は Worker と Reviewer の両方に就ける runtime で、正本は
# orchestrator-worker の tier 表（cursor 列）。script はその写しである。
# 写しは黙ってずれるので、下の drift テストが表と script の両方から model ID を
# 機械的に取り出して突き合わせる。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/skills/agmsg-delegation/scripts/run-cursor-worker.sh"
  SKILL="$REPO_ROOT/catalog/skills/orchestrator-worker/SKILL.md"
  PROJECT="$(mktemp -d)"
  PAYLOAD="$(mktemp)"
  printf 'noop\n' >"$PAYLOAD"
  # cursor-agent 本体を起動させない。allowlist / profile 生成は引数検証と
  # ファイル出力だけなので、実行前に exit させる。
  export AGMSG_CURSOR_BIN="$REPO_ROOT/tests/does-not-exist-cursor-agent"
}

teardown() {
  rm -rf -- "$PROJECT" "$PAYLOAD"
}

# tier 表の Worker / Reviewer 行から cursor の model ID を取り出す。
# claude-* 系と gpt-5.6-sol-xhigh のみが対象で、Codex 列の gpt-5.6-sol /
# gpt-5.6-terra / gpt-6-astra のような2segment id とは正規表現の segment数で
# 区別される（gpt-[0-9.]+-[a-z]+-[a-z]+ は3segment必須）。
skill_models_for() {
  grep -E "^\| $1 " "$SKILL" | grep -oE 'claude-[a-z0-9.-]+|gpt-[0-9.]+-[a-z]+-[a-z]+' | sort -u | tr '\n' ' '
}

# script が role ごとに許可している model を取り出す
script_models_for() {
  sed -n "s/^$1) allowed_models=(\(.*\)) ;;$/\1/p" "$SCRIPT"
}

@test "implement with an allowed model passes the allowlist and fails later, not at validation" {
  run "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -ne 2 ]
  [[ "$output" != *"not allowed for role"* ]]
}

@test "implement with the escalation model also passes the allowlist" {
  run "$SCRIPT" implement "$PROJECT" claude-opus-5-thinking-high "$PAYLOAD"
  [ "$status" -ne 2 ]
  [[ "$output" != *"not allowed for role"* ]]
}

@test "review with an allowed model passes the allowlist and fails later, not at validation" {
  run "$SCRIPT" review "$PROJECT" claude-fable-5-thinking-xhigh "$PAYLOAD"
  [ "$status" -ne 2 ]
  [[ "$output" != *"not allowed for role"* ]]
}

@test "review allows gpt-5.6-sol-xhigh" {
  run "$SCRIPT" review "$PROJECT" gpt-5.6-sol-xhigh "$PAYLOAD"
  [ "$status" -ne 2 ]
  [[ "$output" != *"not allowed for role"* ]]
}

@test "a review-only model is rejected for implement" {
  run "$SCRIPT" implement "$PROJECT" claude-fable-5-thinking-xhigh "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed for role implement"* ]]
}

@test "gpt-5.6-sol-xhigh is rejected for implement" {
  run "$SCRIPT" implement "$PROJECT" gpt-5.6-sol-xhigh "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not allowed for role implement"* ]]
}

@test "an unknown model is rejected for both roles" {
  for role in implement review; do
    run "$SCRIPT" "$role" "$PROJECT" claude-nonexistent-model "$PAYLOAD"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not allowed for role $role"* ]]
  done
}

@test "an unsupported role is rejected" {
  run "$SCRIPT" plan "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unsupported role"* ]]
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

# 以下は profile 生成だけを検証するモード。AGMSG_CURSOR_SANDBOX_PROFILE_ONLY=1 は
# cursor-agent 本体・sandbox-exec・認証のいずれも要求せず、profile の内容だけを
# 確認できる（opencode helper の AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY と同じ役割）。

@test "AGMSG_CURSOR_SANDBOX_PROFILE_ONLY does not require cursor-agent or sandbox-exec" {
  run env AGMSG_CURSOR_SANDBOX_PROFILE_ONLY=1 AGMSG_CURSOR_BIN=/no/such/cursor-agent \
    "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
}

@test "the profile denies read of ~/.cursor and <project>/.cursor" {
  run env AGMSG_CURSOR_SANDBOX_PROFILE_ONLY=1 \
    "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny file-read* (subpath \"$HOME/.cursor\"))"* ]]
  local canon_project
  canon_project="$(cd "$PROJECT" && pwd -P)"
  [[ "$output" == *"(deny file-read* (subpath \"$canon_project/.cursor\"))"* ]]
}

@test "implement allows write to the project; review denies it" {
  run env AGMSG_CURSOR_SANDBOX_PROFILE_ONLY=1 \
    "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
  local canon_project
  canon_project="$(cd "$PROJECT" && pwd -P)"
  [[ "$output" == *"(subpath \"$canon_project\")"* ]]
  [[ "$output" != *"(deny file-write* (subpath \"$canon_project\"))"* ]]

  run env AGMSG_CURSOR_SANDBOX_PROFILE_ONLY=1 \
    "$SCRIPT" review "$PROJECT" claude-fable-5-thinking-xhigh "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(deny file-write* (subpath \"$canon_project\"))"* ]]
}

@test "the profile allows /dev, tmp, runtime_dir, and agmsg state" {
  run env AGMSG_CURSOR_SANDBOX_PROFILE_ONLY=1 \
    "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'(subpath "/dev")'* ]]
  [[ "$output" == *"agmsg"* ]]
}

@test "cursor-agent binary is required to exist for a real launch (default path resolution rejected)" {
  # デフォルト解決先を使わせ、実体が無い環境では起動時に exit 1 になることを確認する
  # (allowlist・profile 生成は通過済みであることを exit != 2 で確認する)。
  run env -u AGMSG_CURSOR_BIN "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  if [[ -x "$HOME/.local/bin/cursor-agent" ]] || command -v cursor-agent >/dev/null 2>&1; then
    skip "cursor-agent is actually installed on this host; binary-missing path cannot be exercised without launching it"
  fi
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not be resolved"* ]]
}

@test "AGMSG_CURSOR_BIN pointing at a mise-shim-shaped path is rejected" {
  local shim_dir="$PROJECT/shims"
  mkdir -p "$shim_dir"
  local shim="$shim_dir/cursor-agent"
  cat >"$shim" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$shim"
  run env AGMSG_CURSOR_BIN="$shim" "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not be resolved"* ]]
}

@test "AGMSG_CURSOR_VERIFIED_VERSION mismatch is rejected before launch" {
  local stub_dir stub
  stub_dir="$(mktemp -d)"
  stub="$stub_dir/cursor-agent"
  cat >"$stub" <<'SH'
#!/bin/sh
case "$1" in
  --version) echo "cursor-agent 1.2.3"; exit 0 ;;
  mcp) echo "No MCP servers configured"; exit 0 ;;
  *) echo "unexpected invocation: $*" >&2; exit 1 ;;
esac
SH
  chmod +x "$stub"
  run env AGMSG_CURSOR_BIN="$stub" AGMSG_CURSOR_VERIFIED_VERSION=9.9.9 \
    "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"AGMSG_CURSOR_VERIFIED_VERSION"* ]]
  rm -rf -- "$stub_dir"
}

@test "a matching AGMSG_CURSOR_VERIFIED_VERSION passes the version gate and reaches the mcp capability check" {
  local stub_dir stub
  stub_dir="$(mktemp -d)"
  stub="$stub_dir/cursor-agent"
  cat >"$stub" <<'SH'
#!/bin/sh
case "$1" in
  --version) echo "cursor-agent 1.2.3"; exit 0 ;;
  mcp) echo "No MCP servers configured"; exit 0 ;;
  *) echo "LAUNCHED: $*"; exit 0 ;;
esac
SH
  chmod +x "$stub"
  run env AGMSG_CURSOR_BIN="$stub" AGMSG_CURSOR_VERIFIED_VERSION=1.2.3 \
    "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LAUNCHED:"* ]]
  [[ "$output" == *"--model claude-sonnet-5-thinking-high"* ]]
  [[ "$output" == *"--trust"* ]]
  [[ "$output" == *"--force"* ]]
  rm -rf -- "$stub_dir"
}

@test "a stub reporting a non-empty mcp list is rejected (fail-closed capability check)" {
  local stub_dir stub
  stub_dir="$(mktemp -d)"
  stub="$stub_dir/cursor-agent"
  cat >"$stub" <<'SH'
#!/bin/sh
case "$1" in
  --version) echo "cursor-agent 1.2.3"; exit 0 ;;
  mcp) echo "1 server configured: some-mcp"; exit 0 ;;
  *) echo "unexpected invocation: $*" >&2; exit 1 ;;
esac
SH
  chmod +x "$stub"
  run env AGMSG_CURSOR_BIN="$stub" "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"did not confirm an empty MCP surface"* ]]
  rm -rf -- "$stub_dir"
}

# --- MCP capability check の回帰（2026-09-18） ---
#
# 当初の判定は "No MCP servers configured" の文字列一致だけだった。cursor は cwd が
# ~/.cursor/projects/<slug>/ を持つ場合に mcp-approvals.json への EPERM を返すため、
# 通常の作業リポジトリでは helper が常に exit で起動を拒否していた。出力形を列挙して
# 両方を受理し、かつ MCP がロードされている出力は拒否する契約を固定する。

@test "the mcp capability check passes from a cwd that has a cursor project entry" {
  cd "$HOME/.apm" || skip "~/.apm not present"
  [ -d "$HOME/.cursor/projects" ] || skip "no cursor project entries on this machine"
  command -v cursor-agent >/dev/null || skip "cursor-agent is not installed"
  run env -u AGMSG_CURSOR_BIN AGMSG_CURSOR_MCP_CHECK_ONLY=1 "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mcp surface confirmed empty"* ]]
}

@test "the mcp capability check passes from a cwd without a cursor project entry" {
  cd /tmp || return 1
  command -v cursor-agent >/dev/null || skip "cursor-agent is not installed"
  run env -u AGMSG_CURSOR_BIN AGMSG_CURSOR_MCP_CHECK_ONLY=1 "$SCRIPT" implement "$PROJECT" claude-sonnet-5-thinking-high "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mcp surface confirmed empty"* ]]
}
