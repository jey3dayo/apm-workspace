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
  PAYLOAD_DIR="$(mktemp -d)"
  PAYLOAD="$PAYLOAD_DIR/payload"
  printf 'noop\n' >"$PAYLOAD"
  # 証拠 root は worker の write_paths（/tmp と TMPDIR）の外に置く必要がある。
  # repo が一時領域に checkout されていれば HOME を使い、どちらも無理なら成立しないので skip する。
  local parent
  for parent in "$REPO_ROOT/tests" "$HOME"; do
    if outside_worker_tmp "$parent"; then
      EVIDENCE_FIXTURE="$(mktemp -d "$parent/.agmsg-evidence.XXXXXX")"
      break
    fi
  done
  [[ -n "${EVIDENCE_FIXTURE:-}" ]] || skip "repo と HOME がどちらも /tmp か TMPDIR の配下にあり、証拠 root を worker の write_paths の外に置けない"
  AGMSG_EVIDENCE_ROOT="$EVIDENCE_FIXTURE"
  export AGMSG_EVIDENCE_ROOT
  # exec される側なので、cwd を出して即 exit するだけのスタブにする。
  printf '#!/bin/sh\nprintf "STUB cwd=%%s\\n" "$(pwd -P)"\nexit 0\n' >"$WORKDIR/stub"
  chmod +x "$WORKDIR/stub"
  # sandbox-exec は macOS 固有なので、ここでは worker の引数・cwd 検証だけを
  # 実行できる最小スタブに置き換え、Linux CI でも同じ契約を検証する。
  printf '#!/bin/sh\nif [ "$1" = "-f" ]; then shift 2; fi\nexec "$@"\n' >"$WORKDIR/sandbox-exec"
  chmod +x "$WORKDIR/sandbox-exec"
}

teardown() {
  if [[ -n "${EVIDENCE_FIXTURE:-}" ]]; then
    chmod -R u+w -- "$EVIDENCE_FIXTURE" 2>/dev/null || true
    rm -rf -- "$EVIDENCE_FIXTURE"
  fi
  rm -rf -- "$WORKDIR" "$PROJECT" "$PAYLOAD_DIR"
}

outside_worker_tmp() {
  local candidate tmp_real tmpdir_real
  candidate="$(cd "$1" && pwd -P)" || return 1
  tmp_real="$(cd /tmp && pwd -P)"
  tmpdir_real="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  [[ "$candidate" != "$tmp_real" && "$candidate" != "$tmp_real"/* &&
    "$candidate" != "$tmpdir_real" && "$candidate" != "$tmpdir_real"/* ]]
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
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

@test "review role writes read-only evidence with the project deny line" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -eq 0 ]
  local canonical dir
  canonical="$(cd "$PROJECT" && pwd -P)"
  dir="$AGMSG_EVIDENCE_ROOT/$(basename "$(dirname "$PAYLOAD")")"
  [ "$(cat "$dir/meta")" = "$(printf 'role=review\nproject=%s' "$canonical")" ]
  grep -qxF "(deny file-write* (subpath \"$canonical\"))" "$dir/profile.sb"
  [ "$(file_mode "$dir/meta")" = 400 ]
  [ "$(file_mode "$dir/profile.sb")" = 400 ]
}

@test "implement role writes evidence without the project deny line" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./stub "$2" implement "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -eq 0 ]
  local canonical dir
  canonical="$(cd "$PROJECT" && pwd -P)"
  dir="$AGMSG_EVIDENCE_ROOT/$(basename "$(dirname "$PAYLOAD")")"
  [ "$(cat "$dir/meta")" = "$(printf 'role=implement\nproject=%s' "$canonical")" ]
  ! grep -qF "(deny file-write* (subpath \"$canonical\"))" "$dir/profile.sb"
}

@test "an existing evidence directory refuses the run before anything launches" {
  mkdir -p "$AGMSG_EVIDENCE_ROOT/$(basename "$(dirname "$PAYLOAD")")"
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Evidence directory already exists"* ]]
  [[ "$output" != *"STUB cwd="* ]]
}

@test "a missing executable is refused before anything launches" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_CLAUDE_BIN=./does-not-exist "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Claude executable not found"* ]]
}

@test "an evidence root under TMPDIR is refused before anything launches" {
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_EVIDENCE_ROOT="$5" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD" "$WORKDIR/evidence"
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlaps worker-writable path"* ]]
  [[ "$output" != *"STUB cwd="* ]]
  [ ! -e "$WORKDIR/evidence/$(basename "$PAYLOAD_DIR")" ]
}

@test "an evidence root symlinked into TMPDIR is refused before anything launches" {
  mkdir "$WORKDIR/real"
  ln -s "$WORKDIR/real" "$EVIDENCE_FIXTURE/link"
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_EVIDENCE_ROOT="$5" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD" "$EVIDENCE_FIXTURE/link"
  [ "$status" -ne 0 ]
  [[ "$output" == *"overlaps worker-writable path"* ]]
  [[ "$output" != *"STUB cwd="* ]]
  [ ! -e "$WORKDIR/real/$(basename "$PAYLOAD_DIR")" ]
}

@test "an evidence root that cannot be created is refused before anything launches" {
  mkdir "$EVIDENCE_FIXTURE/locked"
  chmod 500 "$EVIDENCE_FIXTURE/locked"
  run bash -c 'cd "$1" && PATH="$1:$PATH" AGMSG_EVIDENCE_ROOT="$5" AGMSG_CLAUDE_BIN=./stub "$2" review "$3" "$4"' \
    _ "$WORKDIR" "$SCRIPT" "$PROJECT" "$PAYLOAD" "$EVIDENCE_FIXTURE/locked/root"
  [ "$status" -ne 0 ]
  [[ "$output" != *"STUB cwd="* ]]
}

@test "under the real sandbox the review worker cannot alter its evidence" {
  command -v /usr/bin/sandbox-exec >/dev/null || skip "sandbox-exec is macOS only"
  # 実物の sandbox-exec を通すため PATH 先頭にスタブを置かない。
  printf '%s\n' '#!/bin/sh' \
    'dir="$AGMSG_EVIDENCE_ROOT/$RUN_ID"' \
    'echo STUB tamper' \
    'echo tampered >>"$dir/meta" || true' \
    'rm -f "$dir/profile.sb" || true' \
    'echo forged >"$dir/forged" || true' \
    'exit 0' >"$WORKDIR/tamper"
  chmod +x "$WORKDIR/tamper"
  run env RUN_ID="$(basename "$PAYLOAD_DIR")" AGMSG_CLAUDE_BIN="$WORKDIR/tamper" \
    "$SCRIPT" review "$PROJECT" "$PAYLOAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB tamper"* ]]
  local canonical dir
  canonical="$(cd "$PROJECT" && pwd -P)"
  dir="$(printf '%s\n' "$output" | sed -n 's/.*evidence=//p')"
  [ "$(cat "$dir/meta")" = "$(printf 'role=review\nproject=%s' "$canonical")" ]
  grep -qxF "(deny file-write* (subpath \"$canonical\"))" "$dir/profile.sb"
  [ "$(ls -A "$dir" | sort | tr '\n' ' ')" = "meta profile.sb " ]
}
