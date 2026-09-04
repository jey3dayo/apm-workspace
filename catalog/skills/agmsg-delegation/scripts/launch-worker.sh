#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 || "$2" != "--" ]]; then
	printf 'Usage: %s <run-dir> -- <worker-command> [args...]\n' "$0" >&2
	exit 2
fi

run_dir=$1
shift 2

if [[ ! -d "$run_dir" ]]; then
	printf 'Run directory does not exist: %s\n' "$run_dir" >&2
	exit 2
fi

tmp_root=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
run_dir=$(cd -- "$run_dir" && pwd -P)
case "$run_dir" in
"$tmp_root"/agmsg-delegation.*) ;;
*)
	printf 'Run directory must be a mktemp agmsg-delegation directory under %s: %s\n' "$tmp_root" "$run_dir" >&2
	exit 2
	;;
esac

pid_file="$run_dir/worker.pid"
log_file="$run_dir/worker.log"
exit_file="$run_dir/worker.exit"

if [[ -e "$pid_file" || -e "$log_file" || -e "$exit_file" ]]; then
	printf 'Run directory is not empty: %s\n' "$run_dir" >&2
	exit 2
fi

launchctl_bin=/bin/launchctl
if [[ ! -x "$launchctl_bin" ]]; then
	printf '%s\n' 'launchctl is required for detached macOS worker execution.' >&2
	exit 1
fi

domain="gui/$(id -u)"
label="local.agmsg-delegation.worker.$$.${RANDOM}"
wrapper="$run_dir/worker-wrapper.sh"
plist="$run_dir/worker.plist"
label_file="$run_dir/worker.label"

# codex を親プロセス側で絶対パスへ解決しておく。launchd job は親の環境も cwd も
# 継承せず、mise の shim 解決は cwd と MISE_ENV の両方に依存するため、worker 内では
# codex を解決できない ("No version is set for shim" で起動不能)。
# MISE_ENV が launchd に継承されず、mise の npm 版 codex が node を要する wrapper の
# まま渡ると同じ経路で即死するため、環境を wrapper に明示し、vendor の native binary を優先する。
# worker 内で MISE_ENV を設定する方法は `latest` のネットワーク解決でハングするため使わない。
# このスクリプトは親コンテキストで動くのでここでだけ解決できる。
# claude は mise 管理外 (~/.local/bin) でどこでも解決できるため対象外。
codex_is_native() {
	local description
	[[ -x "$1" ]] || return 1
	description=$(file -b "$1" 2>/dev/null) || return 1
	case "$description" in
	*script*|*text*) return 1 ;;
	Mach-O*|ELF*|PE32*) return 0 ;;
	*) return 1 ;;
	esac
}

resolve_codex_bin() {
	local codex_path=${AGMSG_CODEX_BIN:-}
	local install_root candidate native_path
	if [[ -z "$codex_path" ]]; then
		codex_path=$(mise which codex 2>/dev/null) || codex_path=
	fi
	[[ -n "$codex_path" && -x "$codex_path" ]] || return 1

	if codex_is_native "$codex_path"; then
		printf '%s\n' "$codex_path"
		return 0
	fi

	install_root=$(cd -- "$(dirname -- "$codex_path")/.." 2>/dev/null && pwd -P) || install_root=
	if [[ -n "$install_root" ]]; then
		while IFS= read -r candidate; do
			if codex_is_native "$candidate"; then
				native_path=$candidate
				printf '%s\n' "$native_path"
				return 0
			fi
		done < <(find "$install_root" -type f -path '*/vendor/*/bin/codex' -perm -111 -print 2>/dev/null)
	fi

	# native binary が無い場合は、従来どおり npm wrapper を返して node の PATH 補完へ進む。
	printf '%s\n' "$codex_path"
}

codex_bin_resolved=$(resolve_codex_bin) || codex_bin_resolved=
[[ -n "$codex_bin_resolved" && -x "$codex_bin_resolved" ]] || codex_bin_resolved=

codex_node_dir=
if [[ -n "$codex_bin_resolved" ]] && ! codex_is_native "$codex_bin_resolved"; then
	node_bin=$(mise which node 2>/dev/null) || node_bin=
	if [[ -n "$node_bin" && -x "$node_bin" ]]; then
		codex_node_dir=$(cd -- "$(dirname -- "$node_bin")" 2>/dev/null && pwd -P) || codex_node_dir=
	fi
fi

mise_env=${MISE_ENV:-}

umask 077
{
	printf '%s\n' '#!/usr/bin/env bash' 'set +e'
	if [[ -n "$mise_env" ]]; then
		printf 'export MISE_ENV=%q\n' "$mise_env"
	fi
	if [[ -n "$codex_node_dir" ]]; then
		printf 'export PATH=%q\n' "$codex_node_dir:${PATH:-/usr/bin:/bin}"
	fi
	if [[ -n "$codex_bin_resolved" ]]; then
		printf 'export AGMSG_CODEX_BIN=%q\n' "$codex_bin_resolved"
	fi
	# wrapper 自身が pid を書く。launchctl print のポーリングでは job のプロセス
	# 生成が間に合わず pid を取り逃すため。この pid は launchd job の pid と一致する
	printf 'echo "$$" >%q\n' "$pid_file"
	printf '%q ' "$@"
	printf ' >%q 2>&1\n' "$log_file"
	printf '%s\n' 'status=$?'
	printf 'echo "$status" >%q\n' "$exit_file"
	printf '%s\n' 'exit "$status"'
} >"$wrapper"
chmod 700 "$wrapper"

cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$wrapper</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict></plist>
EOF

if ! "$launchctl_bin" bootstrap "$domain" "$plist"; then
	printf 'launchctl bootstrap failed for %s\n' "$label" >&2
	exit 1
fi

printf '%s\n' "$label" >"$label_file"

# wrapper が pid を書くまで待つ。job が即座に終了した場合も pid は実行前に
# 書かれているため取得できる。上限を超えたら pid 不明として続行する
pid=-
for _ in $(seq 1 40); do
	if [[ -s "$pid_file" ]]; then
		pid=$(<"$pid_file")
		break
	fi
	sleep 0.1
done

printf 'label=%s\npid=%s\nlog=%s\n' "$label" "$pid" "$log_file"
