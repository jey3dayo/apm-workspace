#!/usr/bin/env bash
# 共通ユーティリティ関数
# apm-workspace.sh と native.sh の両方で使用される基本的な関数

have_command() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

error() {
  printf 'error: %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if ! have_command "$1"; then
    fail "$1 not found. Install it first."
  fi
}

require_apm() {
  if ! have_command apm; then
    fail "apm not found. Run 'cd $WORKSPACE_DIR && mise install' (or install it in another shell) before retrying."
  fi
}

home_apm_is_checkout() {
  [ -e "$HOME/.apm/.git" ] || [ -d "$HOME/.apm/catalog" ]
}

default_workspace_dir() {
  if home_apm_is_checkout; then
    printf '%s\n' "$HOME/.apm"
  else
    printf '%s\n' "$REPO_ROOT"
  fi
}

ensure_workspace_repo() {
  require_command git

  if [ ! -e "$WORKSPACE_DIR" ]; then
    log "Cloning $WORKSPACE_REPO into $WORKSPACE_DIR"
    git clone "$WORKSPACE_REPO" "$WORKSPACE_DIR"
  elif [ -d "$WORKSPACE_DIR" ] && [ ! -e "$WORKSPACE_DIR/.git" ]; then
    if [ -n "$(ls -A "$WORKSPACE_DIR" 2>/dev/null)" ]; then
      fail "$WORKSPACE_DIR exists but is not an empty directory or git checkout."
    fi

    log "Cloning $WORKSPACE_REPO into existing empty directory $WORKSPACE_DIR"
    (
      cd "$WORKSPACE_DIR"
      git clone "$WORKSPACE_REPO" .
    )
  elif [ ! -d "$WORKSPACE_DIR" ]; then
    fail "$WORKSPACE_DIR exists but is not a directory."
  fi

  if [ ! -e "$WORKSPACE_DIR/.git" ]; then
    fail "$WORKSPACE_DIR exists but is not a git checkout."
  fi
}

ensure_workspace_scaffold() {
  ensure_workspace_repo

  if [ ! -f "$WORKSPACE_DIR/apm.yml" ]; then
    fail "Missing workspace apm.yml: $WORKSPACE_DIR/apm.yml"
  fi
}

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

relative_file_list() {
  root_dir="$1"
  if [ ! -d "$root_dir" ]; then
    return 0
  fi

  (
    cd "$root_dir"
    find . -type f | sed 's#^\./##' | sort
  )
}
