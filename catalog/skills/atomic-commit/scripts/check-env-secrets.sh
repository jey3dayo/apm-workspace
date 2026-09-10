#!/usr/bin/env bash

set -uo pipefail

# `.env.*` に平文 secret 候補が含まれていないかを、値を出さずに検査する。
#
#   0  平文 secret 候補なし
#   1  候補あり。`<file>: <KEY>` を1行ずつ標準出力へ出す（値は出さない）
#   2  検査を完了できなかった。呼び出し側は stage / commit せず停止する
#
# ## 対応する形式（これ以外は 2 へ倒す）
#
# - `KEY=value`、`export KEY=value`、行頭の空白、`=` 前後の空白
# - 単行の `KEY="value"` / `KEY='value'`（区切りの引用符が同じ行で閉じるもの）
# - `#` で始まるコメント行、空行、CRLF
#
# ## 明示的に拒否する形式（2）
#
# - 引用が同じ行で閉じない値（複数行値）と、区切り引用符が escape された値
# - backtick で囲んだ値
# - BOM、NUL を含むファイル、`KEY=` の形になっていない行
# - regular file でない対象（symlink / gitlink）、type change、conflict 中
#
# 複数行値と escape を追おうとすると、引用状態を早く抜けたときに**値の断片を
# key 名として出力する**——「値を出さない」という契約そのものを破る。追うより
# 拒否するほうが契約を守れる。生の複数行秘密鍵はそもそも stage すべきでない。
#
# ## 検査対象
#
# commit に入るのは index なので、index を working tree と相殺させない。
# diff の追加行ではなく対象版の実体を読む（binary 属性や rename 最適化で
# 追加行が消えても内容を検査できるようにするため）。
#
#   1. index   （`git show :<path>`）
#   2. working tree
#   3. untracked
#
# key 名のヒューリスティックであり、全 secret の検出は保証しない。
#
# Usage: check-env-secrets.sh [<repo-root>]

repo=${1:-.}
cd -- "$repo" || { printf 'check-env-secrets: cannot enter %s\n' "$repo" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || {
	printf 'check-env-secrets: not a git repository: %s\n' "$repo" >&2
	exit 2
}

work=$(mktemp -d) || exit 2
chmod 700 "$work" || { rm -rf -- "$work"; exit 2; }
trap 'rm -rf -- "$work"' EXIT

hits="$work/hits"
: >"$hits" || exit 2

ENV_PATHSPEC=':(glob)**/.env.*'

refuse() {
	printf 'check-env-secrets: %s (%s) -- check by hand\n' "$1" "$2" >&2
	exit 2
}

scan_file() {
	local path=$1
	/usr/bin/awk -v path="$path" '
		BEGIN { SQ = sprintf("%c", 39); BOM = sprintf("%c%c%c", 239, 187, 191) }
		function classify(key, value) {
			if (key == "DOTENV_PUBLIC_KEY") return
			if (value ~ /^encrypted:/) return
			if (key !~ /(SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH|APIKEY|KEY|PAT|DSN)/) return
			printf "%s: %s\n", path, key
		}
		{
			line = $0
			sub(/\r$/, "", line)
			if (NR == 1 && index(line, BOM) == 1) { bad = 1; exit }

			work = line
			sub(/^[ \t]+/, "", work)
			if (work == "" || work ~ /^#/) next
			sub(/^export[ \t]+/, "", work)

			eq = index(work, "=")
			if (eq == 0) { bad = 1; exit }
			key = substr(work, 1, eq - 1)
			value = substr(work, eq + 1)
			sub(/[ \t]+$/, "", key)
			sub(/^[ \t]+/, "", value)
			if (key !~ /^[A-Za-z0-9_]+$/) { bad = 1; exit }

			q = substr(value, 1, 1)
			if (q == "`") { bad = 1; exit }
			if (q == "\"" || q == SQ) {
				# 同じ行で閉じる引用だけを受理する。backslash の次の文字は
				# 区切りとして数えないので、escape された引用符では閉じない。
				rest = substr(value, 2)
				close_at = 0
				i = 1
				n = length(rest)
				while (i <= n) {
					c = substr(rest, i, 1)
					if (c == "\\") { i += 2; continue }
					if (c == q) { close_at = i; break }
					i++
				}
				if (close_at == 0) { bad = 1; exit }
				value = substr(rest, 1, close_at - 1)
			}
			classify(key, value)
		}
		END { if (bad) exit 3 }
	'
}

check_regular_index_entry() {
	local file=$1 mode
	mode=$(git ls-files -s -z -- "$file" 2>/dev/null | LC_ALL=C tr -d '\000' | awk 'NR==1{print $1}')
	case "$mode" in
		100644 | 100755) return 0 ;;
		*) refuse "$file is not a regular file in the index (mode ${mode:-unknown})" cached ;;
	esac
}

scan_group() {
	local mode=$1 list="$work/list.$1" file
	case "$mode" in
		cached) git diff --cached --name-only -z --diff-filter=ACMRT -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
		worktree) git diff --name-only -z --diff-filter=ACMRT -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
		untracked) git ls-files --others --exclude-standard -z -- "$ENV_PATHSPEC" >"$list" 2>/dev/null ;;
	esac || refuse "listing failed" "$mode"

	while IFS= read -r -d '' file; do
		if [ "$mode" = cached ]; then
			check_regular_index_entry "$file"
			git show ":$file" >"$work/blob" 2>/dev/null ||
				refuse "cannot read the staged content of $file" "$mode"
		else
			[ ! -L "$file" ] || refuse "$file is a symlink" "$mode"
			[ -f "$file" ] || refuse "$file is not a regular file" "$mode"
			cat -- "$file" >"$work/blob" 2>/dev/null || refuse "cannot read $file" "$mode"
		fi

		# NUL の判定は shell 側で行う。awk の sprintf("%c", 0) は空文字列になり
		# index() が 1 を返すため、awk 内では判定できない。
		LC_ALL=C tr -d '\000' <"$work/blob" | cmp -s - "$work/blob" ||
			refuse "$file is not text" "$mode"

		scan_file "$file" <"$work/blob" >>"$hits" ||
			refuse "$file uses a .env form this check does not support" "$mode"
	done <"$list"
}

# conflict 中は stage 0 が無く、検査が成立しない。
if [ -n "$(git ls-files -u -z -- "$ENV_PATHSPEC" 2>/dev/null | LC_ALL=C tr -d '\000')" ]; then
	refuse "a .env.* path is unmerged" cached
fi

scan_group cached
scan_group worktree
scan_group untracked

if [ -s "$hits" ]; then
	sort -u "$hits"
	exit 1
fi
exit 0
