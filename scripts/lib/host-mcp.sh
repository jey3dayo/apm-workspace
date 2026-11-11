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

parallel_mcp_manifest_fields() {
  local manifest block url env_name
  manifest="$WORKSPACE_DIR/apm.yml"
  [ -f "$manifest" ] || fail "missing $manifest"
  block="$(
    awk '
      $0 == "    - name: parallel" {
        count++
        capture = count == 1
      }
      capture && $0 != "    - name: parallel" && $0 ~ /^    - name:/ { capture = 0 }
      capture { print }
      END { exit count != 1 }
    ' "$manifest"
  )" || fail "apm.yml must contain exactly one parallel MCP entry"

  [ "$(printf '%s\n' "$block" | grep -cx '      registry: false')" = 1 ] \
    && [ "$(printf '%s\n' "$block" | grep -cx '      transport: http')" = 1 ] \
    || fail "parallel MCP must use the self-defined HTTP manifest shape"
  url="$(printf '%s\n' "$block" | sed -n 's/^      url: \(https:\/\/[^[:space:]]*\)$/\1/p')"
  env_name="$(printf '%s\n' "$block" | sed -n 's/^        Authorization: "Bearer \${\([A-Z_][A-Z0-9_]*\)}"$/\1/p')"
  [ "$url" = "https://mcp.parallel.ai/mcp" ] \
    && [ "$env_name" = PARALLEL_API_KEY ] \
    || fail "parallel MCP must use the official endpoint and PARALLEL_API_KEY header binding"
  printf '%s\t%s\n' "$url" "$env_name"
}

codex_parallel_mcp_matches() {
  local url="$1" env_name="$2" authenticated="$3" details
  details="$(codex mcp get parallel 2>/dev/null)" || return 1
  printf '%s\n' "$details" | grep -Fq -- "url: $url" || return 1
  if [ "$authenticated" = 1 ]; then
    printf '%s\n' "$details" | grep -Fq -- "bearer_token_env_var: $env_name"
  else
    ! printf '%s\n' "$details" | grep -Fq -- "$env_name"
  fi
}

claude_parallel_mcp_matches() {
  local url="$1" env_name="$2" authenticated="$3" details
  details="$(claude mcp get parallel 2>/dev/null)" || return 1
  printf '%s\n' "$details" | grep -Fq -- "Scope: User config" \
    && printf '%s\n' "$details" | grep -Fq -- "$url" \
    || return 1
  if [ "$authenticated" = 1 ]; then
    printf '%s\n' "$details" | grep -Fq -- "\${$env_name}"
  else
    ! printf '%s\n' "$details" | grep -Fq -- "$env_name"
  fi
}

cmd_sync_global_mcp() {
  local fields url env_name authenticated=0 header
  require_command codex
  require_command claude
  fields="$(parallel_mcp_manifest_fields)"
  IFS=$'\t' read -r url env_name <<<"$fields"
  if [ -n "${!env_name:-}" ]; then authenticated=1; fi

  if ! codex_parallel_mcp_matches "$url" "$env_name" "$authenticated"; then
    if codex mcp get parallel >/dev/null 2>&1; then codex mcp remove parallel; fi
    if [ "$authenticated" = 1 ]; then
      codex mcp add parallel --url "$url" --bearer-token-env-var "$env_name"
    else
      codex mcp add parallel --url "$url"
    fi
  fi

  if ! claude_parallel_mcp_matches "$url" "$env_name" "$authenticated"; then
    if claude mcp get parallel >/dev/null 2>&1; then claude mcp remove parallel --scope user; fi
    if [ "$authenticated" = 1 ]; then
      header="Authorization: Bearer \${$env_name}"
      claude mcp add --scope user --transport http parallel "$url" --header "$header"
    else
      claude mcp add --scope user --transport http parallel "$url"
    fi
  fi

  codex_parallel_mcp_matches "$url" "$env_name" "$authenticated" \
    || fail "Codex Parallel MCP verification failed."
  claude_parallel_mcp_matches "$url" "$env_name" "$authenticated" \
    || fail "Claude Parallel MCP verification failed."
  if [ "$authenticated" = 1 ]; then
    workspace_log "Global Parallel MCP configuration uses $env_name at client runtime."
  else
    workspace_log "Global Parallel MCP configuration is anonymous; free tools remain available."
  fi
}

cmd_setup_host_mcp() {
  require_command codex
  require_command claude

  mcp_command=$(resolve_1password_mcp_command) \
    || fail "1Password MCP command not found. Install or enable the 1Password desktop app MCP first."

  if codex_1password_mcp_matches "$mcp_command"; then
    workspace_log "Codex 1Password MCP is already configured: $mcp_command"
  else
    if codex mcp get 1password >/dev/null 2>&1; then
      codex mcp remove 1password
    fi
    codex mcp add 1password -- "$mcp_command"
  fi

  if claude_1password_mcp_matches "$mcp_command"; then
    workspace_log "Claude 1Password MCP is already configured: $mcp_command"
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
  workspace_log "Host-local 1Password MCP configuration is current."
}
