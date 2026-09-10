#!/usr/bin/env bash

set -uo pipefail

# `.env.*` に平文 secret 候補が含まれていないかを、値を出さずに検査する。
#
#   0  平文 secret 候補なし
#   1  候補あり。`<file>: <KEY>` を1行ずつ標準出力へ出す（値は出さない）
#   2  検査を完了できなかった。呼び出し側は stage / commit せず停止する
#
# **diff の追加行ではなく、対象版のファイル全文を解析する。** 追加行だけを見る
# 方式は次を区別できない: 引用された複数行値の途中行が代入やコメントに見える
# 場合（値の一部を key と誤認し、あるいは素通りする）、`.gitattributes` の
# binary / -diff で差分本体が出ない場合、rename 最適化で追加行が消える場合。
# いずれも「追加行が無い＝安全」と読んでしまう。
#
# 検査対象は3つを独立に見る。commit に入るのは index なので、index を
# working tree と相殺させない。
#
#   1. index   （commit に入る内容そのもの。`git show :<path>` で読む）
#   2. working tree（まだ stage されていない状態）
#   3. untracked   （まだ git が知らないファイル）
#
# 解析できないファイル（NUL を含む、引用が閉じない）は 2 へ倒す。未解析を
# 安全と判定しない。
#
# Usage: check-env-secrets.sh [<repo-root>]

repo=${1:-.}
cd -- "$repo" || { printf 'check-env-secrets: cannot enter %s\n' "$repo" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || {
	printf 'check-env-secrets: not a git repository: %s\n' "$repo" >&2
	exit 2
}

# 一時物は専用ディレクトリ1つにまとめ、作成直後に trap を張る。
work=$(mktemp -d) || exit 2
chmod 700 "$work" || { rm -rf -- "$work"; exit 2; }
trap 'rm -rf -- "$work"' EXIT

hits="$work/hits"
: >"$hits" || exit 2

ENV_PATHSPEC=':(glob)**/.env.*'

# dotenv を状態機械で読む。引用された複数行値の内部では代入・コメント判定を
# 行わない。解析できなければ exit 3（呼び出し側が 2 へ変換する）。
# 値の展開・command substitution は一切行わない。
scan_file() {
	local path=$1
	/usr/bin/awk -v path="$path" '
		function classify(key, value,   first) {
			if (key == "DOTENV_PUBLIC_KEY") return
			first = substr(value, 1, 1)
			if (first == "\"" || first == sprintf("%c", 39)) value = substr(value, 2)
			if (value ~ /^encrypted:/) return
			if (key !~ /(SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH|APIKEY|KEY|PAT|DSN)/) return
			printf "%s: %s\n", path, key
		}
		{
			line = $0
			sub(/\r$/, "", line)

			if (open_quote != "") {
				# 引用された値の内部。閉じ引用だけを探し、他は値として捨てる。
				if (index(line, open_quote) > 0) open_quote = ""
				next
			}

			work = line
			sub(/^[ \t]+/, "", work)
			if (work == "" || work ~ /^#/) next
			sub(/^export[ \t]+/, "", work)
			eq = index(work, "=")
			if (eq == 0) { unparsed = 1; exit }
			key = substr(work, 1, eq - 1)
			value = substr(work, eq + 1)
			sub(/[ \t]+$/, "", key)
			sub(/^[ \t]+/, "", value)
			if (key !~ /^[A-Za-z0-9_]+$/) { unparsed = 1; exit }

			q = substr(value, 1, 1)
			if (q == "\"" || q == sprintf("%c", 39)) {
				rest = substr(value, 2)
				if (index(rest, q) == 0) open_quote = q
			}
			classify(key, value)
		}
		END {
			if (open_quote != "") unparsed = 1
			if (unparsed) exit 3
		}
	'
}

scan_group() {
	local mode=$1 list="$work/list.$1" file status
	case "$mode" in
		cached) git diff --cached --name-only -z --diff-filter=ACMR -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
		worktree) git diff --name-only -z --diff-filter=ACMR -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
		untracked) git ls-files --others --exclude-standard -z -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
	esac || {
		printf 'check-env-secrets: listing failed (%s)\n' "$mode" >&2
		exit 2
	}

	while IFS= read -r -d '' file; do
		if [ "$mode" = cached ]; then
			git show ":$file" >"$work/blob" 2>/dev/null || {
				printf 'check-env-secrets: cannot read the staged content of %s\n' "$file" >&2
				exit 2
			}
		else
			cat -- "$file" >"$work/blob" 2>/dev/null || {
				printf 'check-env-secrets: cannot read %s\n' "$file" >&2
				exit 2
			}
		fi

		# NUL を含むファイルは dotenv として解析しない。awk の sprintf("%c", 0) は
		# 空文字列になり index() が 1 を返すため、awk 側では判定できない。
		if ! LC_ALL=C tr -d '\000' <"$work/blob" | cmp -s - "$work/blob"; then
			printf 'check-env-secrets: %s is not text (%s) -- check by hand\n' "$file" "$mode" >&2
			exit 2
		fi

		scan_file "$file" <"$work/blob" >>"$hits"
		status=$?
		[ "$status" -eq 0 ] || {
			printf 'check-env-secrets: %s is not parsable as dotenv (%s) -- check by hand\n' "$file" "$mode" >&2
			exit 2
		}
	done <"$list"
}

scan_group cached
scan_group worktree
scan_group untracked

if [ -s "$hits" ]; then
	sort -u "$hits"
	exit 1
fi
exit 0
