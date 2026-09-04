#!/usr/bin/env bats
#
# run-claude-worker.sh が claude_bin を cd 前に絶対化することを検証する。
#
# 対象 project へ cd する変更を入れたとき、claude_bin だけ相対のまま残った。
# `command -v` は PATH 名を絶対化するがスラッシュを含む引数はそのまま返すため、
# AGMSG_CLAUDE_BIN=./x は cwd 基準の存在確認だけ通過し、cd 先で execvp が失敗した
# （reviewer-fable-spawn の high 指摘。前段の reviewer 指摘を修正したと報告しながら
# 実際には適用されておらず、2 回見逃した）。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/skills/agmsg-delegation/scripts/run-claude-worker.sh"
  WORKDIR="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  PAYLOAD="$(mktemp)"
  printf 'noop\n' >"$PAYLOAD"
  # exec される側なので、cwd を出して即 exit するだけのスタブにする。
  printf '#!/bin/sh\nprintf "STUB cwd=%%s\\n" "$(pwd -P)"\nexit 0\n' >"$WORKDIR/stub"
  chmod +x "$WORKDIR/stub"
  # sandbox-exec は macOS 固有なので、ここでは worker の引数・cwd 検証だけを
  # 実行できる最小スタブに置き換え、Linux CI でも同じ契約を検証する。
  printf '#!/bin/sh\nif [ "$1" = "-f" ]; then shift 2; fi\nexec "$@"\n' >"$WORKDIR/sandbox-exec"
  chmod +x "$WORKDIR/sandbox-exec"
}

teardown() {
  rm -rf -- "$WORKDIR" "$PROJECT" "$PAYLOAD"
}

@test "a relative AGMSG_CLAUDE_BIN still launches after the cd into the project" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB cwd="* ]]
  [[ "$output" != *"execvp"* ]]
}

@test "the worker starts in the target project, not the launcher's cwd" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -eq 0 ]
  # $PROJECT は mktemp -d なので canonical path と比較する。
  local canonical
  canonical="$(cd "$PROJECT" && pwd -P)"
  [[ "$output" == *"STUB cwd=$canonical"* ]]
}

@test "a missing executable is refused before anything launches" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./does-not-exist "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Claude executable not found"* ]]
}
