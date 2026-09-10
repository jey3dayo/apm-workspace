#!/usr/bin/env bash

set -uo pipefail

# 追加差分に平文 secret 候補が混ざっていないかを、値を出さずに検査する。
#
# 判定を終了コードで分ける。空の出力は「secret なし」を意味しない——収集や
# 解析が失敗しても出力は空になるため、呼び出し側が 0 と 2 を区別できないと
# fail-open する（パイプの最終段だけを見る書き方はこれを区別できない）。
#
#   0  平文 secret 候補なし
#   1  候補あり。`<file>: <KEY>` を1行ずつ標準出力へ出す（値は出さない）
#   2  検査を完了できなかった。呼び出し側は stage / commit せず停止する
#
# 検査対象は3つを独立に見る。commit に入るのは index なので、index を
# working tree と相殺させない——HEAD が暗号文・index が平文・working tree が
# 暗号文へ戻っている状態は、working tree だけを見ると差分ゼロに見える。
#
#   1. index vs HEAD        （commit に入る内容そのもの）
#   2. working tree vs index（まだ stage されていない変更）
#   3. untracked            （まだ git が知らないファイル）
#
# key の抽出は行の簡易一致であってフルの dotenv parser ではない。解析できない
# 追加行（複数行値の途中など）は安全側へ倒して 2 を返す。
#
# Usage: check-env-secrets.sh [<repo-root>]

repo=${1:-.}
cd -- "$repo" || { printf 'check-env-secrets: cannot enter %s\n' "$repo" >&2; exit 2; }

# 一時物は専用ディレクトリ1つにまとめ、作成直後に trap を張る。個別に mktemp
# すると、2つ目の作成が失敗した経路で1つ目（収集済みの差分）が残る。
work=$(mktemp -d) || exit 2
chmod 700 "$work" || exit 2
trap 'rm -rf -- "$work"' EXIT

hits="$work/hits"
: >"$hits" || exit 2

ENV_PATHSPEC=':(glob)**/.env.*'

# 追加行から key 名だけを取り出す。path は引数で渡す——diff の `+++` ヘッダから
# 復元すると、Git が引用する特殊なファイル名（tab や quote を含む）で壊れる。
# 解析できない追加行があれば exit 3 で呼び出し側へ知らせる。
scan_diff() {
	local path=$1
	/usr/bin/awk -v path="$path" '
		{
			if (substr($0, 1, 1) != "+") next
			line = substr($0, 2)
			if (line ~ /^\+\+/) next
			sub(/^[ \t]+/, "", line)
			if (line == "" || line ~ /^#/) next
			sub(/^export[ \t]+/, "", line)
			eq = index(line, "=")
			if (eq == 0) { unparsed = 1; next }
			key = substr(line, 1, eq - 1)
			value = substr(line, eq + 1)
			sub(/[ \t]+$/, "", key)
			sub(/^[ \t]+/, "", value)
			if (key !~ /^[A-Za-z0-9_]+$/) { unparsed = 1; next }
			if (key == "DOTENV_PUBLIC_KEY") next
			first = substr(value, 1, 1)
			if (first == "\"" || first == sprintf("%c", 39)) value = substr(value, 2)
			if (value ~ /^encrypted:/) next
			if (key !~ /(SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH|APIKEY|KEY|PAT|DSN)/) next
			printf "%s: %s\n", path, key
		}
		END { if (unparsed) exit 3 }
	'
}

# $1 に列挙コマンド、$2 に diff コマンドの種別を取り、ファイルごとに走査する。
scan_group() {
	local mode=$1 list="$work/list.$1" file status
	case "$mode" in
		cached) git diff --cached --name-only -z -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
		worktree) git diff --name-only -z -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
		untracked) git ls-files --others --exclude-standard -z -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
	esac || {
		printf 'check-env-secrets: listing failed (%s)\n' "$mode" >&2
		exit 2
	}

	while IFS= read -r -d '' file; do
		case "$mode" in
			cached) git diff --cached -U0 -- "$file" >"$work/diff" 2>/dev/null ;;
			worktree) git diff -U0 -- "$file" >"$work/diff" 2>/dev/null ;;
			untracked) git diff --no-index -U0 -- /dev/null "$file" >"$work/diff" 2>/dev/null ;;
		esac
		status=$?
		# --no-index は差分ありで 1 を返す。2 以上だけを失敗として扱う。
		[ "$status" -le 1 ] || {
			printf 'check-env-secrets: diff failed (%s) for %s\n' "$mode" "$file" >&2
			exit 2
		}
		scan_diff "$file" <"$work/diff" >>"$hits"
		status=$?
		[ "$status" -eq 0 ] || {
			printf 'check-env-secrets: unparsable .env line in %s -- check by hand\n' "$file" >&2
			exit 2
		}
	done <"$list"
}

git rev-parse --git-dir >/dev/null 2>&1 || {
	printf 'check-env-secrets: not a git repository: %s\n' "$repo" >&2
	exit 2
}

scan_group cached
scan_group worktree
scan_group untracked

if [ -s "$hits" ]; then
	sort -u "$hits"
	exit 1
fi
exit 0
