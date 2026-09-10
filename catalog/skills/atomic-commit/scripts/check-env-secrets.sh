#!/usr/bin/env bash

set -uo pipefail

# 追加差分に平文 secret 候補が混ざっていないかを、値を出さずに検査する。
#
# 判定を終了コードで分ける。空の出力は「secret なし」を意味しない——収集が
# 失敗しても出力は空になるため、呼び出し側が 0 と 2 を区別できないと
# fail-open する（パイプの最終段だけを見る書き方はこれを区別できない）。
#
#   0  平文 secret 候補なし
#   1  候補あり。`<file>: <KEY>` を1行ずつ標準出力へ出す（値は出さない）
#   2  検査を完了できなかった。呼び出し側は stage せず停止する
#
# Usage: check-env-secrets.sh [<repo-root>]

repo=${1:-.}
cd -- "$repo" || { printf 'check-env-secrets: cannot enter %s\n' "$repo" >&2; exit 2; }

raw=$(mktemp) || exit 2

# tracked: staged と unstaged の両方。pathspec の glob でサブディレクトリも拾う。
if ! git diff -U0 HEAD -- ':(glob)**/.env.*' >"$raw" 2>/dev/null; then
	printf 'check-env-secrets: git diff failed\n' >&2
	exit 2
fi

# untracked: git diff に現れないので --no-index で1件ずつ足す。差分ありの exit 1 は
# 正常なので、2 以上だけを失敗として扱う。
# NUL 区切りはコマンド代入を通すと落ちるので、必ずファイル経由で読む。
list=$(mktemp) || exit 2
trap 'rm -f -- "$raw" "$raw.hits" "$list"' EXIT
if ! git ls-files --others --exclude-standard -z -- ':(glob)**/.env.*' >"$list" 2>/dev/null; then
	printf 'check-env-secrets: git ls-files failed\n' >&2
	exit 2
fi
while IFS= read -r -d '' file; do
	git diff --no-index -U0 /dev/null "$file" >>"$raw" 2>/dev/null
	status=$?
	[ "$status" -le 1 ] || {
		printf 'check-env-secrets: git diff --no-index failed for %s\n' "$file" >&2
		exit 2
	}
done <"$list"

# 値を出さずに `<file>: <KEY>` だけを組み立てる。DOTENV_PUBLIC_KEY は dotenvx の
# 公開メタデータで managed 判定の根拠そのものなので、KEY 群に一致しても除外する。
/usr/bin/awk '
	/^\+\+\+ / { path = substr($0, 7); next }
	/^\+/ {
		line = substr($0, 2)
		sub(/^export /, "", line)
		eq = index(line, "=")
		if (eq == 0) next
		key = substr(line, 1, eq - 1)
		value = substr(line, eq + 1)
		if (key !~ /^[A-Za-z0-9_]+$/) next
		if (key == "DOTENV_PUBLIC_KEY") next
		if (value ~ /^["'"'"']?encrypted:/) next
		if (key !~ /(SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH|APIKEY|KEY|PAT|DSN)/) next
		printf "%s: %s\n", (path == "" ? "?" : path), key
	}
' "$raw" | sort -u >"$raw.hits" || exit 2

if [ -s "$raw.hits" ]; then
	cat "$raw.hits"
	rm -f -- "$raw.hits"
	exit 1
fi
rm -f -- "$raw.hits"
exit 0
