resolve_source_sha() {
  local ref="$1" sha
  if sha=$(git -C "$REPO_ROOT" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null); then
    printf '%s\n' "$sha"
  elif [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "$ref"
  else
    fail "--source-ref $ref is neither a commit of $REPO_ROOT nor a full 40-hex SHA"
  fi
}

# Rewrites the two floating workspace refs (catalog#main, manual-skills#main) into SHA pins, and the packages in
# EXTERNAL_PACKAGE_MAP into the structured form, and converts the root executable approvals for user-scope APM.
render_manifest() {
  local sha="$1" workspace_only="$2"
  [ -f "$ROOT_MANIFEST" ] || fail "missing $ROOT_MANIFEST"
  printf '# Rendered by scripts/native.sh from apm.yml with this repository pinned at %s. Do not edit; re-render.\n' "$sha"
  printf '# native-render: workspace_only=%s\n' "$workspace_only"
  awk -v sha="$sha" -v url="$SOURCE_URL" -v only="$workspace_only" -v map="$EXTERNAL_PACKAGE_MAP" '
    function convert(   i, prefix, rest, pin) {
      for (i = 1; i <= n; i++) {
        prefix = "    - " key[i] "#"
        if (index($0, prefix) != 1) continue
        rest = substr($0, length(prefix) + 1)
        pin = substr(rest, 1, 40)
        if (length(pin) != 40 || pin !~ /^[0-9a-f]+$/) continue
        if (length(rest) > 40 && substr(rest, 41, 1) != " ") continue
        printf "    - git: %s\n      ref: %s\n      skills:\n        - %s\n", repo[i], pin, skill[i]
        converted[i]++
        return 1
      }
      return 0
    }
    BEGIN {
      required["github.com/fujibee/agmsg"] = 1
      required["github.com/ibelick/ui-skills"] = 1
      required["github.com/tt-a1i/archify/archify"] = 1
      n = split(map, entries, " ")
      for (i = 1; i <= n; i++) {
        split(entries[i], kv, "=")
        split(kv[2], rs, ":")
        key[i] = kv[1]; repo[i] = rs[1]; skill[i] = rs[2]
      }
    }
    /^[^[:space:]#]/ && $0 !~ /^[A-Za-z_][A-Za-z0-9_-]*:/ { invalid = 1 }
    /^executables:/ {
      if ($0 !~ /^executables:[[:space:]]*$/) invalid = 1
      if (exec_seen++) invalid = 1
      section = "executables"; group = ""; next
    }
    /^allowExecutables:/ { invalid = 1; next }
    section == "executables" && $0 !~ /^[^ #]/ {
      if ($0 ~ /^[[:space:]]*(#.*)?$/) next
      if ($0 == "  allow:") { if (allow_seen++) invalid = 1; next }
      if ($0 ~ /^    github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+:$/) {
        if (!allow_seen || (current != "" && !bins[current])) invalid = 1
        current = $0; sub(/^    /, "", current); sub(/:$/, "", current)
        if (grants[current]++) invalid = 1
        order[++na] = current; next
      }
      if ($0 == "      bin: true" && current != "") { if (bins[current]++) invalid = 1; next }
      invalid = 1; next
    }
    /^[^ #]/ { section = $0; sub(/:.*/, "", section); group = "" }
    section == "dependencies" && /^  [a-z]+:/ { group = $1 }
    section == "dependencies" && group == "apm:" && /^    - / {
      dep = $0; sub(/^    - /, "", dep); sub(/^git: /, "", dep); sub(/#.*/, "", dep); sub(/[[:space:]].*$/, "", dep)
      if (dep !~ /:|\// || dep ~ /^https?:/) next_dep = ""
      else { next_dep = "github.com/" dep; deps[next_dep]++ }
    }
    /^    - jey3dayo\/apm-workspace\/(catalog|manual-skills)#main[ ]*$/ {
      pkg = $0
      sub(/^.*apm-workspace\//, "", pkg)
      sub(/#main.*$/, "", pkg)
      printf "    - git: %s\n      path: %s\n      ref: %s\n", url, pkg, sha
      pinned[pkg]++
      next
    }
    !only && convert() { next }
    only && section == "dependencies" && group == "mcp:" { next }
    only && section == "dependencies" && group == "apm:" && !/^  apm:/ { next }
    { print }
    END {
      ok = (pinned["catalog"] == 1 && pinned["manual-skills"] == 1 && exec_seen == 1 && allow_seen == 1 && na > 0 && !invalid)
      for (i = 1; i <= na; i++) if (bins[order[i]] != 1) ok = 0
      if (!only) for (i = 1; i <= n; i++) if (converted[i] != 1) ok = 0
      if (!only) for (i = 1; i <= na; i++) if (deps[order[i]] != 1) ok = 0
      if (!only) for (id in required) if (grants[id] != 1) ok = 0
      if (ok && !only) {
        print "allowExecutables:"
        for (i = 1; i <= na; i++) printf "  %s:\n    bin: true\n", order[i]
      }
      exit !ok
    }
  ' "$ROOT_MANIFEST" || fail "apm.yml must list the workspace packages and mapped packages exactly once, and contain valid bin-only executable approvals for listed dependencies"
}

# APM reads a root with Python's splitlines(): CRLF and a lone CR both end a line.
root_lines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

has_marker() {
  local first
  first="$(root_lines "$1" | LC_ALL=C sed -n '/[^[:space:]]/{p;q;}')"
  [ "${first#"$GENERATED_ROOT_MARKER"}" != "$first" ]
}

# apm_cli/compilation/build_id.py: the 12-hex Build ID is the sha256 of the file without that line, lines joined by
# "\n". Any edit after compile breaks the match.
has_valid_build_id() {
  local pattern='^<!-- Build ID: [0-9a-f]{12} -->$' recorded computed
  recorded="$(root_lines "$1" | grep -E "$pattern" | sed -E 's/^<!-- Build ID: ([0-9a-f]{12}) -->$/\1/')"
  [ "$(printf '%s\n' "$recorded" | grep -c .)" = 1 ] || return 1
  computed="$(root_lines "$1" | grep -vE "$pattern" | awk '{ if (n++) printf "\n"; printf "%s", $0 }' | sha256 | cut -c1-12)"
  [ "$recorded" = "$computed" ]
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi
}

edited_generated_roots() {
  local home="$1" root
  for root in $COMPILED_ROOTS; do
    if [ -f "$home/$root" ] && has_marker "$home/$root" && ! has_valid_build_id "$home/$root"; then
      printf '%s\n' "$home/$root"
    fi
  done
}

cmd_render() {
  parse_options "$@"
  [ -n "$SOURCE_REF" ] || fail "render needs --source-ref"
  render_manifest "$(resolve_source_sha "$SOURCE_REF")" "$WORKSPACE_ONLY"
}

cmd_plan() {
  parse_options "$@"
  local sha
  sha="$(resolve_source_sha "${SOURCE_REF:-HEAD}")"
  printf '# Source: %s at %s\n' "$SOURCE_URL" "$sha"
  if [ -z "$(git -C "$REPO_ROOT" branch -r --contains "$sha" 2>/dev/null)" ]; then
    printf '# Warning: no remote branch contains %s yet; apm cannot fetch it until it is pushed.\n' "$sha"
  fi
  printf '# Consumer manifest (written to <HOME>/.apm/apm.yml by apply):\n\n'
  render_manifest "$sha" "$WORKSPACE_ONLY"
  cat <<EOF

# apply --home <disposable HOME> --source-ref $sha would run:
#   1. stop if <HOME>/apm.yml exists (apm reads its executable approvals there instead of <HOME>/.apm/apm.yml), if an
#      APM-generated root there was edited after compile ($COMPILED_ROOTS), or if a symlink or hard link
#      inside that HOME reaches outside it
#   2. stop if <HOME>/.apm/config.json holds more than default_client and prefer_ssh; keep a differing
#      <HOME>/.apm/apm.yml as apm.yml.<UTC>.bak
#   3. write the manifest above
#   4. apm install -g --only apm --trust-bin, from an empty environment plus HOME, PATH, locale, git config locations and a
#      TMPDIR in HOME; MCP servers stay as they are
#   5. apm compile -g --clean, the same way
# apply --real-home is blocked. The real HOME is switched by migrate --real-home --source-ref $sha --rehearsal <dir>, which
# needs a clean rehearse --migrate of a backup of that HOME first and would run:
#   1. stop if <HOME>/.apm is a checkout (.git or catalog/) or this repository lies inside it
#   2. stop unless the rehearsal's result.txt is mode=migrate, for the same HOME and ref, with no failed step, no lost
#      file outside the allowlist, and no skipped baseline; then the guards of apply, over the paths apm writes
#   3. copy ${MIGRATE_UNTOUCHED_FILES// /, } (owner-only) to <HOME>/.apm/native-migrate-<UTC>.untouched; save the agmsg links
#   4. write the manifest above, move $MIGRATE_ROOTS
#      to <root>.bak-<UTC> (nothing is deleted)
#   5. apm install -g --only apm --trust-bin, apm compile -g --clean, then copy back the top-level entries apm did not deploy
#      (a link that leaves its root is copied; a link that leaves the HOME or is broken fails); restore the agmsg links;
#      stop if a file of the roots is gone outside the allowlist (the same check as the rehearsal, listed in
#      <HOME>/.apm/native-migrate-<UTC>.lost.txt) or if the files of step 3 changed
#   6. on any failure, undo step 4 (migrate-rollback --stamp <UTC> does the same later) and put the files of step 3 back,
#      keeping what migrate left as <file>.changed-<UTC>. It prints the stamp.
# Not deployed by APM, and left to the manual steps in docs/native-distribution.md: agmsg db/teams links,
# catalog/rules and catalog/claude/rules, private skills, OpenCode and Pi instructions, host-local MCP.
# This plan wrote nothing.
EOF
}

cmd_apply() {
  parse_options "$@"
  [ "$REAL_HOME" = 0 ] || fail "applying to the real HOME is blocked: apm install deletes skills the old writer deployed. migrate (after a clean rehearse --migrate) is the command that switches the real HOME; migrate-rollback and reinstate only undo or complete it (docs/native-distribution.md)."
  [ -n "$SOURCE_REF" ] || fail "apply needs --source-ref; deploying never moves a pin on its own"
  [ -n "$HOME_DIR" ] || fail "apply needs --home <disposable HOME>"
  local home sha edited links manifest
  home="$(assert_disposable_home "$HOME_DIR")"
  if ! native_lock_held "$home"; then native_lock_command "$home" apply "$@"; return; fi
  sha="$(resolve_source_sha "$SOURCE_REF")"
  assert_default_apm_config "$home"
  assert_no_home_manifest "$home"
  edited="$(edited_generated_roots "$home")"
  [ -z "$edited" ] || fail "these roots keep APM's marker but were edited after compile, and apm compile would overwrite them:
$edited
Delete the marker line to keep the file as hand-written, or move it aside, then re-run."

  links="$(shared_entries "$home")"
  [ -z "$links" ] || fail "these entries inside $home may share their data with files outside it, so writing them would change those files:
$links
Move them aside or make them plain directories and files of this HOME."

  manifest="$(render_manifest "$sha" "$WORKSPACE_ONLY")"
  install_manifest "$home" "$manifest"

  run_apm_install "$home"
  run_apm "$home" compile -g --clean
}

install_manifest() {
  local home="$1" manifest="$2" tmp
  mkdir -p "$home/.apm"
  # A new file renamed into place, so a hard link at apm.yml keeps the other file's contents.
  tmp="$(mktemp "$home/.apm/.apm.yml.XXXXXX")"
  printf '%s\n' "$manifest" >"$tmp"
  if [ -f "$home/.apm/apm.yml" ] && ! cmp -s "$tmp" "$home/.apm/apm.yml"; then
    keep_previous_manifest "$home"
  fi
  mv -f "$tmp" "$home/.apm/apm.yml"
}

keep_previous_manifest() {
  local home="$1" stamp bak n=1
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  bak="$home/.apm/apm.yml.$stamp.bak"
  while [ -e "$bak" ] || [ -L "$bak" ]; do
    bak="$home/.apm/apm.yml.$stamp.$n.bak"
    n=$((n + 1))
  done
  cp -p "$home/.apm/apm.yml" "$bak"
  log "kept the previous manifest as $bak"
}
