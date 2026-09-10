#!/usr/bin/env bats
#
# check-env-secrets.sh の対応形式と終了コードを固定する。
#
# この helper は 2026-09-10 に 5 周のレビューを要した。毎回「作成者のテストは
# 通るが、作成者が思いつかなかった入力で落ちる」形だったため、既報の欠陥を
# fixture として固定し、以後は人手レビューでなくテストで守る。
#
#   0  平文 secret 候補なし
#   1  候補あり（`<file>: <KEY>`。値は出さない）
#   2  検査不成立（未対応構文・非 text・非 regular file・conflict・収集失敗）
#
# 値がどの経路でも出力されないことを SENTINEL で assert する。実在の秘密値は
# 使わない。

SENTINEL="SENTINEL-VALUE-MUST-NOT-LEAK"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO_ROOT/catalog/skills/atomic-commit/scripts/check-env-secrets.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  # helper の一時物が残らないことを見るため、専用の TMPDIR を与える。
  SCRATCH="$BATS_TEST_TMPDIR/scratch"
  mkdir -p "$REPO" "$SCRATCH"
  # ユーザーの global gitignore が `.env*` を無視していると、fixture が untracked
  # にも tracked にもならず全ケースが 0 になる。テストは環境から切り離す。
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  git -C "$REPO" init -q .
  git -C "$REPO" config core.excludesFile /dev/null
  printf 'x\n' >"$REPO/README"
  git -C "$REPO" add README
  git -C "$REPO" -c user.email=t@example -c user.name=t commit -qm init
}

check() {
  run env TMPDIR="$SCRATCH" "$SCRIPT" "$REPO"
}

commit_env() {
  git -C "$REPO" add -- "$1"
  git -C "$REPO" -c user.email=t@example -c user.name=t commit -qm "add $1"
}

# 内容そのものを検査させるテストはこちらを使う。commit まで進めると3つの
# グループのどれにも入らず、helper は「対象なし」で 0 を返すため検査にならない。
stage_env() {
  git -C "$REPO" add -- "$1"
}

# 失敗時に「何が期待と違ったか」を CI ログへ残す。bats は落ちたテストの出力だけを
# 表示するため、通常実行のノイズにはならない。
dump_repo_state() {
  printf 'status=%s\n' "$status"
  printf 'output=%s\n' "$output"
  printf 'branch=%s\n' "$(git -C "$REPO" branch --show-current)"
  printf 'porcelain:\n%s\n' "$(git -C "$REPO" status --porcelain)"
  printf 'unmerged:\n%s\n' "$(git -C "$REPO" ls-files -u)"
}

assert_no_sentinel() {
  [[ "$output" != *"$SENTINEL"* ]]
}

assert_scratch_clean() {
  [ -z "$(ls -A "$SCRATCH")" ]
}

@test "a dotenvx-managed file passes and leaves no temporary files" {
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  assert_scratch_clean
}

@test "a plain secret staged in the index is reported even when the work tree hides it" {
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  commit_env .env.production
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=%s\n' "$SENTINEL" >"$REPO/.env.production"
  git -C "$REPO" add .env.production
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.production: API_KEY"* ]]
  assert_no_sentinel
  assert_scratch_clean
}

@test "an untracked .env in a subdirectory is reported with its path" {
  mkdir -p "$REPO/sub"
  printf 'SENTRY_DSN=%s\n' "$SENTINEL" >"$REPO/sub/.env.staging"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"sub/.env.staging: SENTRY_DSN"* ]]
  assert_no_sentinel
}

@test "a path holding a tab survives into the report" {
  mkdir -p "$REPO/sub"
  printf 'API_SECRET=%s\n' "$SENTINEL" >"$REPO/sub/.env.tab	name"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"API_SECRET"* ]]
  assert_no_sentinel
}

@test "content marked binary by gitattributes is still inspected" {
  printf 'API_KEY=%s\n' "$SENTINEL" >"$REPO/.env.bin"
  printf '.env.bin binary\n' >"$REPO/.gitattributes"
  git -C "$REPO" add .env.bin .gitattributes
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.bin: API_KEY"* ]]
  assert_no_sentinel
}

@test "a staged change is inspected through the index" {
  printf 'A=1\nB=2\n' >"$REPO/.env.production"
  commit_env .env.production
  printf 'A=1\nB=2\nAPI_TOKEN=%s\n' "$SENTINEL" >"$REPO/.env.production"
  git -C "$REPO" add .env.production
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.production: API_TOKEN"* ]]
  assert_no_sentinel
}

@test "the index and the work tree are scanned independently" {
  printf 'A=1\n' >"$REPO/.env.production"
  commit_env .env.production
  printf 'A=1\nSTAGED_TOKEN=%s\n' "$SENTINEL" >"$REPO/.env.production"
  git -C "$REPO" add .env.production
  printf 'A=1\nSTAGED_TOKEN=%s\nUNSTAGED_SECRET=%s\n' "$SENTINEL" "$SENTINEL" >"$REPO/.env.production"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAGED_TOKEN"* ]]
  [[ "$output" == *"UNSTAGED_SECRET"* ]]
  assert_no_sentinel
}

@test "a regular file turned into a symlink is refused as a type change" {
  printf 'API_KEY=%s\n' "$SENTINEL" >"$REPO/.env.production"
  commit_env .env.production
  printf 'API_KEY=%s\n' "$SENTINEL" >"$BATS_TEST_TMPDIR/outside"
  rm "$REPO/.env.production"
  ln -s "$BATS_TEST_TMPDIR/outside" "$REPO/.env.production"
  git -C "$REPO" add .env.production
  check
  [ "$status" -eq 2 ]
  assert_no_sentinel
}

@test "a rename keeps the content under inspection" {
  printf 'API_TOKEN=%s\n' "$SENTINEL" >"$REPO/.env.old"
  commit_env .env.old
  git -C "$REPO" mv .env.old .env.new
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.new: API_TOKEN"* ]]
  assert_no_sentinel
}

@test "deleting a file is not treated as a finding" {
  printf 'API_TOKEN=%s\n' "$SENTINEL" >"$REPO/.env.production"
  commit_env .env.production
  git -C "$REPO" rm -q .env.production
  check
  [ "$status" -eq 0 ]
  assert_no_sentinel
}

@test "CRLF blank lines do not stop the check" {
  printf 'SOME_HOST=v\r\n\r\nOTHER=w\r\n' >"$REPO/.env.crlf"
  stage_env .env.crlf
  check
  [ "$status" -eq 0 ]
}

@test "the dotenvx public key does not trip the gate" {
  printf 'DOTENV_PUBLIC_KEY=dummy-public\nAPI_KEY="encrypted:dummy"\n' >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 0 ]
}

@test "a quoted value that closes on the same line is inspected" {
  printf 'API_SECRET="%s"\n' "$SENTINEL" >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.production: API_SECRET"* ]]
  assert_no_sentinel
}

@test "a quote left open across lines is refused instead of guessed" {
  printf 'NOTE="first\nSECRET_FRAGMENT=%s\nEND=tail"\n' "$SENTINEL" >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 2 ]
  [[ "$output" != *"SECRET_FRAGMENT"* ]]
  assert_no_sentinel
}

@test "an escaped delimiter does not end the quote" {
  printf 'NOTE="a\\"\nSECRET_FRAGMENT=%s\nEND=tail"\n' "$SENTINEL" >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 2 ]
  [[ "$output" != *"SECRET_FRAGMENT"* ]]
  assert_no_sentinel
}

@test "a backtick value is refused" {
  printf 'NOTE=`first\nSECRET_FRAGMENT=%s\nEND=last`\n' "$SENTINEL" >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 2 ]
  [[ "$output" != *"SECRET_FRAGMENT"* ]]
  assert_no_sentinel
}

@test "a BOM is refused rather than parsed" {
  printf '\xef\xbb\xbfAPI_KEY=%s\n' "$SENTINEL" >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 2 ]
  assert_no_sentinel
}

@test "a file holding NUL is refused" {
  printf 'A=1\x00API_KEY=%s\n' "$SENTINEL" >"$REPO/.env.nul"
  check
  [ "$status" -eq 2 ]
  assert_no_sentinel
}

@test "a line that is not an assignment is refused" {
  printf 'API_KEY=ok\nnot an assignment\n' >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 2 ]
}

@test "a symlink is refused instead of followed" {
  printf 'API_KEY=%s\n' "$SENTINEL" >"$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$REPO/.env.link"
  check
  [ "$status" -eq 2 ]
  assert_no_sentinel
}

@test "an unmerged path refuses the check" {
  printf 'A=1\n' >"$REPO/.env.production"
  commit_env .env.production
  git -C "$REPO" checkout -q -b other
  printf 'A=2\n' >"$REPO/.env.production"
  git -C "$REPO" add .env.production
  git -C "$REPO" -c user.email=t@example -c user.name=t commit -qm other
  git -C "$REPO" checkout -q -
  printf 'A=3\n' >"$REPO/.env.production"
  git -C "$REPO" add .env.production
  git -C "$REPO" -c user.email=t@example -c user.name=t commit -qm main
  # `-c user.*` はその 1 コマンドにしか効かない。setup が global/system config を
  # 無効化しているため、identity を渡さない merge は host の自動生成に依存する。
  # macOS は生成値を受け入れるが Linux は拒否し、merge が 128 で止まって conflict
  # が生まれない（CI 限定失敗の原因）。fixture を host から独立させる。
  run git -C "$REPO" -c user.email=t@example -c user.name=t merge other
  # merge が conflict しなければ未マージ経路に入らず、helper は「対象なし」で 0 を
  # 返す。conflict の成立をここで固定しないと、原因が最後の assert 1 行に潰れる。
  [ "$status" -eq 1 ] || { dump_repo_state; return 1; }
  check
  [ "$status" -eq 2 ] || { dump_repo_state; return 1; }
}

@test "a directory that is not a git repository refuses the check" {
  run env TMPDIR="$SCRATCH" "$SCRIPT" "$BATS_TEST_TMPDIR/scratch"
  [ "$status" -eq 2 ]
}

@test "comments, exports, blank lines, and values holding # or = are handled" {
  printf '# comment\n\nexport DB_HOST=localhost\nURL=https://example/?a=1#frag\nAPI_KEY=encrypted:dummy\n' >"$REPO/.env.production"
  stage_env .env.production
  check
  [ "$status" -eq 0 ]
}
