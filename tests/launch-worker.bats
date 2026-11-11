#!/usr/bin/env bats
#
# launch-worker.sh が書く launchd wrapper の環境引き継ぎを検証する。
#
# launchd job は親の環境を継承しないため、helper が読む上書き変数のうち
# wrapper に書かれないものは spawn 経路で黙って落ちる（effort high 指定の worker が
# xhigh で起動した）。引き継ぐのは allowlist の 4 変数だけで、未設定・空・allowlist 外
# （秘密を含み得る変数を含む）は wrapper に書かない。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/.apm/skills/agmsg-delegation/scripts/launch-worker.sh"
  WORKDIR="$(mktemp -d)"
  RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agmsg-delegation.XXXXXX")"
  WRAPPER="$RUN_DIR/worker-wrapper.sh"

  # bootstrap を成功扱いで即 return する。実 launchd job は起動せず、pid ファイルだけ
  # 書いて launch-worker.sh の pid 待ちループを抜けさせる。
  printf '#!/bin/sh\nprintf 0 >"$(dirname "$3")/worker.pid"\nexit 0\n' >"$WORKDIR/launchctl"
  chmod +x "$WORKDIR/launchctl"
  export AGMSG_LAUNCHCTL_BIN="$WORKDIR/launchctl"
  # mise による codex 解決を走らせず、PATH / AGMSG_CODEX_BIN の export も wrapper に出さない。
  export AGMSG_CODEX_BIN="$WORKDIR/does-not-exist-codex"

  unset MISE_ENV AGMSG_WORKER_EFFORT AGMSG_REVIEWER_EFFORT AGMSG_WORKER_MCP_ALLOW AGMSG_OPENCODE_VARIANT
}

teardown() {
  rm -rf -- "$WORKDIR" "$RUN_DIR"
}

launch() {
  run "$SCRIPT" "$RUN_DIR" -- true
  [ "$status" -eq 0 ]
  [ -f "$WRAPPER" ]
}

# wrapper の `export NAME=...` 行を空の環境で評価し、値を取り出す（quote 形式に依存しない）。
exported_value() {
  env -i bash -c 'eval "$(grep "^export $2=" "$1")"; printf %s "${!2}"' _ "$WRAPPER" "$1"
}

# bats は `set -e` 下で動くため、途中の `! grep` は失敗しても検査にならない。
wrapper_lacks() {
  if grep -q -- "$1" "$WRAPPER"; then
    printf 'wrapper contains: %s\n' "$1" >&2
    return 1
  fi
}

@test "4 つの上書き変数が設定済みなら wrapper に期待値で export される" {
  local mcp_allow='server one $HOME "quoted"'
  AGMSG_WORKER_EFFORT=high \
    AGMSG_REVIEWER_EFFORT=medium \
    AGMSG_WORKER_MCP_ALLOW="$mcp_allow" \
    AGMSG_OPENCODE_VARIANT=max \
    launch

  [ "$(exported_value AGMSG_WORKER_EFFORT)" = "high" ]
  [ "$(exported_value AGMSG_REVIEWER_EFFORT)" = "medium" ]
  [ "$(exported_value AGMSG_WORKER_MCP_ALLOW)" = "$mcp_allow" ]
  [ "$(exported_value AGMSG_OPENCODE_VARIANT)" = "max" ]
}

@test "未設定の変数は wrapper に現れない" {
  AGMSG_WORKER_EFFORT=high launch

  grep -q '^export AGMSG_WORKER_EFFORT=' "$WRAPPER"
  wrapper_lacks AGMSG_REVIEWER_EFFORT
  wrapper_lacks AGMSG_WORKER_MCP_ALLOW
  wrapper_lacks AGMSG_OPENCODE_VARIANT
}

@test "空文字の変数は wrapper に現れない" {
  AGMSG_WORKER_EFFORT= \
    AGMSG_REVIEWER_EFFORT= \
    AGMSG_WORKER_MCP_ALLOW= \
    AGMSG_OPENCODE_VARIANT= \
    launch

  wrapper_lacks AGMSG_WORKER_EFFORT
  wrapper_lacks AGMSG_REVIEWER_EFFORT
  wrapper_lacks AGMSG_WORKER_MCP_ALLOW
  wrapper_lacks AGMSG_OPENCODE_VARIANT
}

@test "allowlist 外の変数は値ごと wrapper に現れない" {
  AGMSG_SOMETHING_ELSE=leak-agmsg \
    SECRET_TOKEN=leak-secret \
    AGMSG_WORKER_EFFORT=high \
    launch

  wrapper_lacks AGMSG_SOMETHING_ELSE
  wrapper_lacks SECRET_TOKEN
  wrapper_lacks leak-agmsg
  wrapper_lacks leak-secret
}

@test "既存の MISE_ENV の引き継ぎを保つ" {
  MISE_ENV=ci launch

  [ "$(exported_value MISE_ENV)" = "ci" ]
}

@test "worker plist escapes XML-special characters in the wrapper path" {
  local xml_tmpdir="$WORKDIR/tmp&<>xml"
  local xml_run_dir xml_wrapper
  mkdir -p "$xml_tmpdir"
  xml_run_dir="$(mktemp -d "$xml_tmpdir/agmsg-delegation.XXXXXX")"
  xml_run_dir="$(cd -- "$xml_run_dir" && pwd -P)"
  xml_wrapper="$xml_run_dir/worker-wrapper.sh"

  run env TMPDIR="$xml_tmpdir" "$SCRIPT" "$xml_run_dir" -- true

  [ "$status" -eq 0 ]
  python3 - "$xml_run_dir/worker.plist" "$xml_wrapper" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as plist_file:
    plist = plistlib.load(plist_file)

assert plist["ProgramArguments"] == ["/bin/bash", sys.argv[2]]
PY
}
