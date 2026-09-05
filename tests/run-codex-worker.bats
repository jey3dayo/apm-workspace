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

# 以下は CODEX_HOME 経路の fail-open 回帰テスト。
#
# profile_target の既定値が $HOME/.codex 直書きだった間、CODEX_HOME を設定した環境では
# profile を置く場所と Codex が読む場所が食い違い、`-p` が exit 0 で base config へ
# 落ちていた。script 側は install も cmp も成功するので、read-only 境界が消えたことに
# 誰も気づけない（reviewer-spawn-final の final-review blocker）。

@test "the review profile is deployed into the worker home the reviewer actually reads" {
  local fake_home stub
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/codex"
  # profile 配置は codex 本体の存在確認より後なので、到達させるには実行可能な
  # スタブが要る。生成 home は EXIT trap で消えるため、起動時点で中身を確認する。
  stub="$fake_home/fake-codex"
  cat >"$stub" <<'SH'
#!/bin/sh
printf 'HOME_IS: %s\n' "$CODEX_HOME"
if [ -f "$CODEX_HOME/agmsg-review.config.toml" ]; then
  printf 'PROFILE_BEGIN\n'
  cat "$CODEX_HOME/agmsg-review.config.toml"
  printf 'PROFILE_END\n'
fi
exit 0
SH
  chmod +x "$stub"
  CODEX_HOME="$fake_home/codex" AGMSG_CODEX_BIN="$stub" \
    run "$SCRIPT" review "$PROJECT" gpt-5.6-sol "$PAYLOAD"
  [ "$status" -eq 0 ]
  # reviewer が読む home は base home ではなく生成された home である。
  [[ "$output" != *"HOME_IS: $fake_home/codex"* ]]
  [[ "$output" == *"PROFILE_BEGIN"* ]]
  # 正本の中身がそのまま届いている（fail-open で base config へ落ちていない）。
  local marker
  marker="$(head -1 "$REPO_ROOT/catalog/skills/agmsg-delegation/agmsg-review.config.toml")"
  [[ "$output" == *"$marker"* ]]
  # base home も $HOME/.codex も profile の置き場にはしない。
  [ ! -f "$fake_home/codex/agmsg-review.config.toml" ]
  rm -rf -- "$fake_home"
}

# 以下は worker が継承する MCP と plugin の最小化。
#
# 実運用で leaf worker が global MCP をそのまま引き継ぎ、Voicevox・Context7・CUA・
# memory lookup まで起動した（CyMaster PR892 のフィールド報告）。認証情報 (1password)
# や GUI 操作 (computer-use / node_repl) を渡すことは能力面の境界を広げるので、
# allowlist で明示したものだけ通す。
#
# 個別キーの上書きでは plugin 由来の MCP を止められない（`-c plugins."x@y".
# enabled=false` は codex 0.153.2 で無視されることを実測済み）。そのため script は
# base config を複製して plugin・非 allowlist の MCP・notify を落とした専用
# CODEX_HOME を worker へ渡す。下のテストは「worker が見る config」を検証する。

mcp_fixture() {
  local home=$1
  mkdir -p "$home"
  cat >"$home/config.toml" <<'TOML'
model = "gpt-5.6-luna"
notify = [
  "/Applications/Some.app/notify",
  "turn-ended",
]

[mcp_servers.context7]
command = "npx"

[mcp_servers.jina-reader]
url = "https://example.invalid/mcp"

[mcp_servers.1password]
command = "/usr/local/bin/1password-mcp"

[mcp_servers.mcp-simple-voicevox]
command = "npx"

[mcp_servers.mcp-simple-voicevox.tools.speak]
enabled = true

[plugins."computer-history@openai-bundled"]
enabled = true

[marketplaces.openai-bundled]
source_type = "local"

[sandbox_workspace_write]
network_access = false
TOML
  printf '{"token":"unused"}\n' >"$home/auth.json"
}

# codex 本体は起動させず、worker が実際に見る CODEX_HOME の中身を書き出す。
# 生成した home は script の EXIT trap で消えるため、起動時点で読む必要がある。
arg_stub() {
  local path=$1
  cat >"$path" <<'SH'
#!/bin/sh
printf 'ARGS: %s\n' "$*"
printf 'HOME_IS: %s\n' "$CODEX_HOME"
if [ -L "$CODEX_HOME/auth.json" ]; then printf 'AUTH_SYMLINK\n'; fi
if [ -f "$CODEX_HOME/config.toml" ]; then
  printf 'CONFIG_BEGIN\n'
  cat "$CODEX_HOME/config.toml"
  printf 'CONFIG_END\n'
else
  printf 'NO_CONFIG\n'
fi
exit 0
SH
  chmod +x "$path"
}

@test "only the allowlisted MCP servers survive for a worker" {
  local home stub
  home="$(mktemp -d)/codex"; mcp_fixture "$home"
  stub="$(mktemp -d)/stub"; arg_stub "$stub"
  CODEX_HOME="$home" AGMSG_CODEX_BIN="$stub" \
    run "$SCRIPT" implement "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -eq 0 ]
  # worker は base home ではなく生成された home を見る。
  [[ "$output" != *"HOME_IS: $home"* ]]
  # 既定 allowlist は context7 と jina-reader。
  [[ "$output" == *"[mcp_servers.context7]"* ]]
  [[ "$output" == *"[mcp_servers.jina-reader]"* ]]
  # 認証情報と通知は必ず落ちる。入れ子の tools 節も一緒に落ちる。
  [[ "$output" != *"[mcp_servers.1password]"* ]]
  [[ "$output" != *"[mcp_servers.mcp-simple-voicevox]"* ]]
  [[ "$output" != *"tools.speak"* ]]
  # plugin 由来の MCP は個別キーで止められないので、定義ごと落とす。
  [[ "$output" != *"[plugins."* ]]
  [[ "$output" != *"[marketplaces"* ]]
  # 人間向けの通知先へ worker の payload を流さない。
  [[ "$output" != *"turn-ended"* ]]
  # base の他の設定は残す。
  [[ "$output" == *"[sandbox_workspace_write]"* ]]
  [[ "$output" == *"model = \"gpt-5.6-luna\""* ]]
  # auth は複製せず共有する。
  [[ "$output" == *"AUTH_SYMLINK"* ]]
}

@test "AGMSG_WORKER_MCP_ALLOW replaces the default allowlist" {
  local home stub
  home="$(mktemp -d)/codex"; mcp_fixture "$home"
  stub="$(mktemp -d)/stub"; arg_stub "$stub"
  CODEX_HOME="$home" AGMSG_WORKER_MCP_ALLOW=1password AGMSG_CODEX_BIN="$stub" \
    run "$SCRIPT" implement "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[mcp_servers.1password]"* ]]
  # 既定で通っていた 2 つが、明示しなければ落ちる（allowlist は置換であって追加ではない）。
  [[ "$output" != *"[mcp_servers.context7]"* ]]
  [[ "$output" != *"[mcp_servers.jina-reader]"* ]]
}

@test "a CODEX_HOME without config.toml leaves the worker home without one" {
  local home stub
  home="$(mktemp -d)/codex"; mkdir -p "$home"
  stub="$(mktemp -d)/stub"; arg_stub "$stub"
  CODEX_HOME="$home" AGMSG_CODEX_BIN="$stub" \
    run "$SCRIPT" implement "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_CONFIG"* ]]
}

@test "the generated worker home is removed after the run" {
  local home stub
  home="$(mktemp -d)/codex"; mcp_fixture "$home"
  stub="$(mktemp -d)/stub"; arg_stub "$stub"
  CODEX_HOME="$home" AGMSG_CODEX_BIN="$stub" \
    run "$SCRIPT" implement "$PROJECT" gpt-5.6-luna "$PAYLOAD"
  [ "$status" -eq 0 ]
  local generated
  generated="$(printf '%s\n' "$output" | sed -n 's/^HOME_IS: //p')"
  [ -n "$generated" ]
  [ ! -e "$generated" ]
}
