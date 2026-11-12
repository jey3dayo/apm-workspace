#!/usr/bin/env bash
set -euo pipefail

# Installs the external dependencies with apm itself in a throwaway HOME, using the manifest native.sh renders,
# because `apm audit` only sees deployed files. Exit 1: apm blocked a package. Exit 2: no verdict (network, tool).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLACEHOLDER_SHA="0000000000000000000000000000000000000000"
SECURITY_BLOCK_PATTERN='^\[x\][[:space:]]+Blocked: .+ contains critical |[0-9]+ critical security finding\(s\)'
WORK_DIR=""
APM_BIN="${APM_BIN:-}"
PROBE_LOG=""

usage() {
  printf 'usage: %s manifest [apm.yml] | holds [dependency-holds.txt]\n' "$(basename "$0")" >&2
  exit 2
}

indeterminate() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

resolve_apm() {
  if [ -n "$APM_BIN" ]; then return; fi
  # A mise shim cannot resolve its tool once HOME is replaced, so pin the real binary first.
  APM_BIN="$(cd "$REPO_ROOT" && mise which apm 2>/dev/null)" || APM_BIN="$(command -v apm || true)"
  [ -n "$APM_BIN" ] || indeterminate "apm not found (install with mise install)"
}

# native.sh render resolves the repository from its own location, so it runs from a staged copy holding the manifest.
render_probe_manifest() {
  local manifest="$1" only="${2:-}" stage
  stage="$(mktemp -d "$WORK_DIR/render.XXXXXX")"
  mkdir -p "$stage/scripts"
  cp -R "$SCRIPT_DIR/." "$stage/scripts/"
  cp "$manifest" "$stage/apm.yml"
  bash "$stage/scripts/native.sh" render --source-ref "$PLACEHOLDER_SHA" |
    awk -v only="$only" -f "$SCRIPT_DIR/lib/manifest-ref-normalize.awk" -f "$SCRIPT_DIR/lib/manifest-external-deps.awk"
}

# Returns 0 when apm installs the manifest, 1 when apm blocks it, 2 for any other failure.
probe_install() {
  local manifest="$1" home status=0
  home="$(mktemp -d "$WORK_DIR/home.XXXXXX")"
  mkdir -p "$home/.apm"
  cp "$manifest" "$home/.apm/apm.yml"
  PROBE_LOG="$home.log"

  # Public repositories only, so fetch over HTTPS: a CI runner has no SSH key.
  (
    cd "$home"
    env HOME="$home" TMPDIR="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
      XDG_STATE_HOME="$home/.state" XDG_DATA_HOME="$home/.local/share" APM_NON_INTERACTIVE=1 NO_COLOR=1 COLUMNS=500 \
      GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=2 \
      GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git@github.com: \
      GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=ssh://git@github.com/ \
      "$APM_BIN" install -g --only apm --trust-bin </dev/null
  ) >"$PROBE_LOG" 2>&1 || status=$?

  [ "$status" -eq 0 ] && return 0
  if grep -Eq "$SECURITY_BLOCK_PATTERN" "$PROBE_LOG"; then return 1; fi
  return 2
}

print_failure_summary() {
  if grep -Eq "$SECURITY_BLOCK_PATTERN" "$PROBE_LOG"; then
    grep -E "$SECURITY_BLOCK_PATTERN" "$PROBE_LOG"
  else
    tail -n 15 "$PROBE_LOG"
  fi
}

cmd_manifest() {
  local manifest="${1:-$REPO_ROOT/apm.yml}" probe_manifest status=0
  [ -f "$manifest" ] || indeterminate "manifest not found: $manifest"
  probe_manifest="$WORK_DIR/manifest.yml"
  render_probe_manifest "$manifest" >"$probe_manifest" || indeterminate "could not render a probe manifest from $manifest"

  probe_install "$probe_manifest" || status=$?
  if [ "$status" -eq 0 ]; then
    printf 'ok: apm install accepted the external dependencies of %s\n' "$manifest"
    return 0
  fi
  print_failure_summary >&2
  if [ "$status" -eq 1 ]; then
    printf 'error: apm install blocked the external dependencies of %s\n' "$manifest" >&2
    return 1
  fi
  indeterminate "apm install failed without a security finding for $manifest"
}

latest_tag() {
  local refs
  refs="$(git ls-remote --tags "$1")" || return 2
  awk '
    {
      name = $2
      sub(/^refs\/tags\//, "", name)
      peeled = (name ~ /\^\{\}$/)
      sub(/\^\{\}$/, "", name)
      if (name !~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/) next
      if (peeled || !(name in sha)) sha[name] = $1
    }
    END {
      for (name in sha) {
        version = name
        sub(/^v/, "", version)
        print version, name, sha[name]
      }
    }
  ' <<<"$refs" | LC_ALL=C sort -V -k1,1 | tail -n 1 | awk '{ print $2, $3 }'
}

default_branch_head() {
  local out
  out="$(git ls-remote "$1" HEAD)" || return 2
  awk 'NR == 1 { print $1 }' <<<"$out"
}

# Prints "<ref-label> <sha>" when apm accepts the candidate, nothing when it blocks it.
accepted_candidate() {
  local repo="$1" label="$2" sha="$3" manifest="$WORK_DIR/hold-manifest.yml" status=0
  render_probe_manifest "$REPO_ROOT/apm.yml" "$repo#$sha" >"$manifest" ||
    indeterminate "could not render a probe manifest from $REPO_ROOT/apm.yml"
  probe_install "$manifest" || status=$?
  case "$status" in
    0) printf '%s %s\n' "$label" "$sha" ;;
    1) ;;
    *)
      print_failure_summary >&2
      indeterminate "apm install failed without a security finding for $repo $label"
      ;;
  esac
}

releasable_candidate() {
  local repo="$1" held="$2" url="https://github.com/$1" tags tag_name="" tag_sha="" head_sha="" found=""

  tags="$(latest_tag "$url")" || indeterminate "git ls-remote --tags failed for $repo"
  read -r tag_name tag_sha <<<"$tags"
  head_sha="$(default_branch_head "$url")" || indeterminate "git ls-remote HEAD failed for $repo"

  if [ -n "$tag_sha" ] && [ "$tag_sha" != "$held" ]; then
    found="$(accepted_candidate "$repo" "$tag_name" "$tag_sha")"
  fi
  if [ -z "$found" ] && [ -n "$head_sha" ] && [ "$head_sha" != "$held" ] && [ "$head_sha" != "$tag_sha" ]; then
    found="$(accepted_candidate "$repo" HEAD "$head_sha")"
  fi
  printf '%s' "$found"
}

emit_github_output() {
  local releasable="$1" title="$2" body="$3"
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  {
    printf 'releasable=%s\n' "$releasable"
    printf 'title<<PROBE_EOF\n%s\nPROBE_EOF\n' "$title"
    printf 'body<<PROBE_EOF\n%s\nPROBE_EOF\n' "$body"
  } >>"$GITHUB_OUTPUT"
}

cmd_holds() {
  local holds="${1:-$REPO_ROOT/docs/dependency-holds.txt}"
  local repo held reason candidate ref sha titles="" body="" releasable=0
  [ -f "$holds" ] || indeterminate "holds file not found: $holds"

  while read -r repo held reason; do
    case "$repo" in "" | "#"*) continue ;; esac
    candidate="$(releasable_candidate "$repo" "$held")"
    if [ -z "$candidate" ]; then
      printf 'still held: %s (held at %s)\n' "$repo" "$held"
      continue
    fi
    read -r ref sha <<<"$candidate"
    releasable=1
    printf 'releasable: %s %s (%s)\n' "$repo" "$ref" "$sha"
    titles="${titles:+$titles, }$repo $ref"
    body="${body:+$body$'\n\n'}- ${repo}: ${ref} (${sha}) の apm install が通った。保留中の SHA は ${held}。理由: ${reason}"
  done <"$holds"

  if [ "$releasable" -eq 0 ]; then
    printf 'no release candidates: every hold is still blocked\n'
    emit_github_output 0 "" ""
    return 0
  fi

  body="$body"$'\n\n''解除の手順: docs/dependency-holds.txt の該当行を消し、apm.yml の pin と apm.lock.yaml を上げ、docs/package-decisions.md に理由を記録して、mise run native:sync の rehearsal で確かめる。'
  emit_github_output 1 "保留中の依存に解除候補: $titles" "$body"
}

main() {
  [ "$#" -ge 1 ] || usage
  local subcommand="$1"
  shift
  case "$subcommand" in manifest | holds) ;; *) usage ;; esac
  command -v git >/dev/null || indeterminate "git not found"

  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  resolve_apm

  "cmd_$subcommand" "$@"
}

main "$@"
