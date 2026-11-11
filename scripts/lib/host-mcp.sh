resolve_1password_mcp_command() {
  for command_name in 1password-mcp onepassword-mcp; do
    if have_command "$command_name"; then
      command -v "$command_name"
      return 0
    fi
  done

  # Overridable so tests can neutralize host-installed app paths; unset means the real list.
  onepassword_app_paths=${APM_1PASSWORD_MCP_APP_PATHS-"/Applications/1Password.app/Contents/MacOS/onepassword-mcp /opt/1Password/onepassword-mcp"}
  for command_path in $onepassword_app_paths; do
    if [ -x "$command_path" ]; then
      printf '%s\n' "$command_path"
      return 0
    fi
  done

  if have_command cmd.exe && have_command wslpath; then
    windows_path=$(cmd.exe /d /c where 1password-mcp.exe 2>/dev/null | tr -d '\r' | sed -n '1p') \
      || windows_path=""
    if [ -n "$windows_path" ]; then
      wslpath -u "$windows_path"
      return 0
    fi
  fi

  return 1
}

codex_1password_mcp_matches() {
  expected_command=$1
  mcp_details=$(codex mcp get 1password 2>/dev/null) || return 1
  printf '%s\n' "$mcp_details" | grep -Fq -- "command: $expected_command"
}

claude_1password_mcp_matches() {
  expected_command=$1
  mcp_details=$(claude mcp get 1password 2>/dev/null) || return 1
  printf '%s\n' "$mcp_details" | grep -Fq -- "Scope: User config" \
    && printf '%s\n' "$mcp_details" | grep -Fq -- "Command: $expected_command"
}

cmd_setup_host_mcp() {
  require_command codex
  require_command claude

  mcp_command=$(resolve_1password_mcp_command) \
    || fail "1Password MCP command not found. Install or enable the 1Password desktop app MCP first."

  if codex_1password_mcp_matches "$mcp_command"; then
    log "Codex 1Password MCP is already configured: $mcp_command"
  else
    if codex mcp get 1password >/dev/null 2>&1; then
      codex mcp remove 1password
    fi
    codex mcp add 1password -- "$mcp_command"
  fi

  if claude_1password_mcp_matches "$mcp_command"; then
    log "Claude 1Password MCP is already configured: $mcp_command"
  else
    if claude mcp get 1password >/dev/null 2>&1; then
      claude mcp remove 1password --scope user
    fi
    claude mcp add --scope user 1password -- "$mcp_command"
  fi

  codex_1password_mcp_matches "$mcp_command" \
    || fail "Codex 1Password MCP verification failed."
  claude_1password_mcp_matches "$mcp_command" \
    || fail "Claude 1Password MCP verification failed."
  log "Host-local 1Password MCP configuration is current."
}
