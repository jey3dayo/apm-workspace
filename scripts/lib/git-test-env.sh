# shellcheck shell=bash
#
# Git hooks export GIT_DIR / GIT_INDEX_FILE (and friends) pointing at the
# repository that runs the hook. A suite that calls plain `git init`,
# `git config` or `git commit` inside its temp dir then writes into that
# repository instead of its fixture. On 2026-10-21 a pre-push
# `mise run test:sh` set core.bare=true, replaced the local user identity and
# added test commits plus an `other` branch in the real checkout.
#
# Source this file and call apm_isolate_git_env before starting any suite.
# $1: file to use as the global git config (default /dev/null).

apm_isolate_git_env() {
	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \
		GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE \
		GIT_QUARANTINE_PATH GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
	# Everything git itself treats as repository-local (covers additions in newer git).
	local v
	for v in $(git rev-parse --local-env-vars 2>/dev/null); do
		unset "$v"
	done
	# GIT_CONFIG_COUNT pairs override every config file, so drop the pairs too.
	for v in $(compgen -e); do
		case "$v" in GIT_CONFIG_KEY_* | GIT_CONFIG_VALUE_*) unset "$v" ;; esac
	done

	# Suites must neither read nor write the user's ~/.gitconfig or /etc/gitconfig.
	export GIT_CONFIG_GLOBAL="${1:-/dev/null}"
	export GIT_CONFIG_NOSYSTEM=1

	# Repository discovery must not climb out of the temp area into a checkout.
	local ceil="" dir phys
	for dir in "${TMPDIR:-/tmp}" /tmp; do
		dir="${dir%/}"
		[ -n "$dir" ] || continue
		ceil="${ceil:+$ceil:}$dir"
		if phys="$(cd "$dir" 2>/dev/null && pwd -P)" && [ "$phys" != "$dir" ]; then
			ceil="$ceil:$phys"
		fi
	done
	export GIT_CEILING_DIRECTORIES="$ceil${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
}
