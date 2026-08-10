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

umask 077
{
	printf '%s\n' '#!/usr/bin/env bash' 'set +e'
	printf '%q ' "$@"
	printf ' >%q 2>&1\n' "$log_file"
	printf '%s\n' 'status=$?' "printf '%s\\n' \"\$status\" >$(printf '%q' "$exit_file")" 'exit "$status"'
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
pid=$("$launchctl_bin" print "$domain/$label" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\);$/\1/p' | head -1)
printf '%s\n' "${pid:--}" >"$pid_file"

printf 'label=%s\npid=%s\nlog=%s\n' "$label" "${pid:--}" "$log_file"
