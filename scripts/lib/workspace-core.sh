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

tracked_catalog_dir() {
  printf '%s/%s\n' "$WORKSPACE_DIR" "$CATALOG_DIR_NAME"
}

tracked_catalog_skills_root() {
  printf '%s/.apm/skills\n' "$(tracked_catalog_dir)"
}

tracked_catalog_agents_root() {
  printf '%s/.apm/agents\n' "$(tracked_catalog_dir)"
}

tracked_catalog_commands_root() {
  printf '%s/commands\n' "$(tracked_catalog_dir)"
}

tracked_catalog_rules_root() {
  printf '%s/rules\n' "$(tracked_catalog_dir)"
}

tracked_catalog_claude_rules_root() {
  printf '%s/claude/rules\n' "$(tracked_catalog_dir)"
}

tracked_catalog_instructions_path() {
  printf '%s/.apm/instructions/%s\n' "$(tracked_catalog_dir)" "$CATALOG_INSTRUCTIONS_FILE_NAME"
}
