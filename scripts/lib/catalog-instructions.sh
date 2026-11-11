# What APM renders from an instruction without applyTo: the body with the frontmatter removed and leading
# blank lines stripped (apm_cli/integration/instruction_integrator.py, _convert_to_claude_rules).
catalog_instructions_body() {
  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter { if ($0 == "---") in_frontmatter = 0; next }
    !started && $0 == "" { next }
    { started = 1; print }
  ' "$1"
}

write_catalog_instructions_body() {
  destination_path="$1"
  body_path=$(mktemp "${TMPDIR:-/tmp}/apm-instructions-body.XXXXXX")
  catalog_instructions_body "$(tracked_catalog_instructions_path)" >"$body_path"
  copy_managed_catalog_file "$body_path" "$destination_path"
  rm -f "$body_path"
}

# Blob ids of every guide body this workspace has written into a root: each committed catalog/AGENTS.md, the
# rendered body of each committed instruction version, and the current body. Outside a git checkout only the
# current body is known.
legacy_catalog_instructions_blobs() {
  instructions_relative_path="$CATALOG_DIR_NAME/.apm/instructions/$CATALOG_INSTRUCTIONS_FILE_NAME"
  version_body=$(mktemp "${TMPDIR:-/tmp}/apm-instructions-version.XXXXXX")
  {
    catalog_instructions_body "$(tracked_catalog_instructions_path)" | git hash-object --stdin
    { git -C "$WORKSPACE_DIR" log --all --format= --raw --no-abbrev -- "$CATALOG_DIR_NAME/AGENTS.md" 2>/dev/null || true; } |
      awk 'NF >= 4 && $4 !~ /^0+$/ { print $4 }'
    { git -C "$WORKSPACE_DIR" log --all --format= --raw --no-abbrev -- "$instructions_relative_path" 2>/dev/null || true; } |
      awk 'NF >= 4 && $4 !~ /^0+$/ { print $4 }' | sort -u |
      while IFS= read -r instruction_blob; do
        git -C "$WORKSPACE_DIR" cat-file blob "$instruction_blob" >"$version_body" 2>/dev/null || continue
        catalog_instructions_body "$version_body" | git hash-object --stdin
      done
  } | sort -u
  rm -f "$version_body"
}

is_legacy_catalog_instructions_copy() {
  candidate_path="$1"
  known_blobs="$2"
  candidate_blob=$(git hash-object --no-filters -- "$candidate_path") || return 1
  grep -qxF -- "$candidate_blob" <<<"$known_blobs"
}

# APM reads a root with Python's universal newlines, so CRLF and a lone CR count as LF; a BOM is kept as text.
apm_root_lines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

# Mirrors APM's `content.lstrip().startswith(AGENTS_MD_GENERATED_MARKER)` (apm_cli/compilation/user_root_context.py).
# The leading set is Python's str.isspace() in UTF-8 bytes, matched byte-wise under LC_ALL=C.
# One awk reads the file: an early exit behind a pipe would SIGPIPE the writer and fail the pipeline under pipefail.
apm_root_has_marker() {
  LC_ALL=C awk -v marker="$APM_GENERATED_ROOT_MARKER" '
    BEGIN {
      leading_space = "^([\t\n\v\f\r\034\035\036\037 ]|\302[\205\240]|\341\232\200|\342\200[\200-\212\250\251\257]|\342\201\237|\343\200\200)+"
    }
    { sub(/\r$/, ""); gsub(/\r/, "\n"); sub(leading_space, "") }
    $0 != "" { found = index($0, marker) == 1; exit }
    END { exit !found }
  ' "$1"
}

# Mirrors apm_cli/compilation/build_id.py has_valid_build_id: the 12-hex Build ID is the sha256 of the file with that
# line removed and the remaining lines joined by "\n", so any edit after compile breaks the match.
has_valid_apm_build_id() {
  build_id_line='^<!-- Build ID: [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] -->$'
  recorded_build_id=$(apm_root_lines "$1" | awk -v pattern="$build_id_line" '
    $0 ~ pattern { count++; build_id = substr($0, 16, 12) }
    END { if (count == 1) print build_id }
  ')
  [ -n "$recorded_build_id" ] || return 1
  computed_build_id=$(apm_root_lines "$1" | awk -v pattern="$build_id_line" '
    $0 ~ pattern { next }
    { if (joined++) printf "\n"; printf "%s", $0 }
  ' | file_sha256 - | cut -c1-12)
  [ "$recorded_build_id" = "$computed_build_id" ]
}

# Classifies a root context file: absent, not-regular, generated (written by apm compile and unchanged since),
# edited-generated (APM's marker kept but edited after compile), legacy (a byte copy of a catalog guide the retired
# legacy sync wrote), or hand-written (anything else, which only its owner may change).
user_root_state() {
  root_path="$1"
  known_blobs="$2"
  if [ ! -e "$root_path" ] && [ ! -L "$root_path" ]; then
    printf 'absent\n'
  elif [ -L "$root_path" ] || [ ! -f "$root_path" ]; then
    printf 'not-regular\n'
  elif apm_root_has_marker "$root_path"; then
    if has_valid_apm_build_id "$root_path"; then
      printf 'generated\n'
    else
      printf 'edited-generated\n'
    fi
  elif is_legacy_catalog_instructions_copy "$root_path" "$known_blobs"; then
    printf 'legacy\n'
  else
    printf 'hand-written\n'
  fi
}

# OpenCode reads ~/.config/opencode/AGENTS.md before falling back to ~/.claude/CLAUDE.md;
# APM writes that file only for an opencode target, and listing opencode would also hand it the agents it rejects.
# A hand-written ~/.claude/CLAUDE.md is what OpenCode reads today, so the guide must not displace it.
sync_opencode_instructions() {
  [ -f "$(tracked_catalog_instructions_path)" ] || return 0
  known_blobs=$(legacy_catalog_instructions_blobs)
  opencode_state=$(user_root_state "$OPENCODE_INSTRUCTIONS_OUTPUT" "$known_blobs")
  case "$opencode_state" in
    legacy) write_catalog_instructions_body "$OPENCODE_INSTRUCTIONS_OUTPUT" ;;
    absent)
      claude_state=$(user_root_state "$HOME/.claude/CLAUDE.md" "$known_blobs")
      case "$claude_state" in
        absent | legacy | generated) write_catalog_instructions_body "$OPENCODE_INSTRUCTIONS_OUTPUT" ;;
        *) log "Not writing $OPENCODE_INSTRUCTIONS_OUTPUT: OpenCode falls back to $HOME/.claude/CLAUDE.md ($claude_state), which is not the catalog guide." ;;
      esac
      ;;
    *) warn "Leaving $OPENCODE_INSTRUCTIONS_OUTPUT as is ($opencode_state): it is not a copy of any committed version of the catalog guide, so OpenCode reads it instead of the guide. If it is a copy deployed from an uncommitted guide, move it aside and re-run sync:opencode." ;;
  esac
}

# Writes only the OpenCode guide; it is safe on a native HOME.
cmd_sync_opencode() {
  require_command git
  sync_opencode_instructions
}
