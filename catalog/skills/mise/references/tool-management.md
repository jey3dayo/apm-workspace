# Tool Version Management - Comprehensive Guide

This document provides detailed guidance on managing language runtimes, CLI tools, and global packages using mise as a unified tool manager.

## Core Philosophy: Centralized Package Management

### Why Centralization?

1. Single Source of Truth: One file tracks all dependencies
2. Version Control: Tools and versions committed with code
3. Team Consistency: Everyone uses the same tool versions
4. Cross-Platform: Works identically on macOS, Linux, Windows (WSL)
5. No Global Pollution: No accidental drift from `npm i -g` or `pip install --user`

## Version Pinning Policy

- For committed repository configs and CI, do not record floating package channels. Resolve the newest acceptable version first, then write the concrete version into `[tools]`.
- For npm and pipx tools, treat the version as part of the repository contract. A moving package channel can change CI behavior without a code diff.
- For pipx-backed tools, mise may route installs through uv or pipx. When dependency age controls are active, the pip fallback can pass pip's `--uploaded-prior-to`; that requires a new enough pip. Pinning the verified package version keeps installs current without making CI depend on a moving resolver target.
- For personal global configs, rolling channels are a local preference, but do not copy them into shared repository examples.

### Exception: pnpm (bootstrap only, loose major pin)

pnpm はこのピン方針の例外。mise の役割はブートストラップだけにし、メジャーで緩くピンする:

```toml
[tools]
pnpm = "12" # bootstrap only; exact version is owned by package.json "packageManager"
```

- 正確なバージョンの正本は各リポジトリの `package.json` の `packageManager` フィールド。pnpm 10+ の self-management（`managePackageManagerVersions`、デフォルト有効）が `packageManager` を読んで自動で該当バージョンに切り替えるため、mise 側で厳密ピンすると二重管理になる
- 厳密ピンの実害例: `mise.toml` が `pnpm = "10.29.3"`、`packageManager` が `pnpm@11.16.0` でドリフトすると、実行されるのは self-management が切り替えた 11 系になり、mise のピンは実効性がないまま誤解だけ生む
- corepack は採用しない。Node.js TSC が 2025-03 に Node 25+ からの corepack 同梱終了を決定しており（外部インストールが必要な別ツール化）、「Node に付いてくる corepack で pnpm を管理」という前提は成立しない

## Configuration Structure

### Standard Layout

```toml
# mise/config.toml (or project-specific mise.toml)
[tools]
# ========================================
# Runtimes (Language Implementations)
# ========================================
node = "<verified-version>"         # Node.js runtime
python = "<verified-version>"          # Python with specific version
ruby = "<verified-version>"
go = "<verified-version>"
rust = "<verified-version>"
lua = "5.1.5"            # Specific version for compatibility (e.g., LuaRocks/Neovim)
luajit = "<verified-version>"

# ========================================
# CLI Tools (Standalone Binaries)
# ========================================
ghq = "<verified-version>"            # Repository manager
github-cli = "<verified-version>"    # gh command
shellcheck = "<verified-version>"    # Shell script linter
yamllint = "<verified-version>"      # YAML linter
taplo = "<verified-version>"         # TOML formatter/linter

# ========================================
# NPM Global Packages
# ========================================
"npm:@bufbuild/protoc-gen-es" = "<verified-version>"
"npm:@connectrpc/protoc-gen-connect-es" = "<verified-version>"
"npm:@fsouza/prettierd" = "<verified-version>"
"npm:@openai/codex" = "<verified-version>"
"npm:aicommits" = "<verified-version>"
"npm:husky" = "<verified-version>"
"npm:markdown-link-check" = "<verified-version>"
"npm:markdownlint-cli2" = "<verified-version>"
"npm:neovim" = "<verified-version>"
"npm:npm" = "<verified-version>"
"npm:npm-check-updates" = "<verified-version>"
"npm:textlint" = "<verified-version>"
"npm:textlint-rule-preset-ja-technical-writing" = "<verified-version>"

# ========================================
# Python Global Packages (via pipx)
# ========================================
"pipx:black" = "<verified-version>"
"pipx:ruff" = "<verified-version>"
"pipx:poetry" = "<verified-version>"
```

### Config Hierarchy

mise supports multiple config locations with clear precedence:

1. Project-local: `./mise.toml` (highest priority)
2. User global: `~/.config/mise/config.toml`
3. System-wide: `/etc/mise/config.toml` (lowest priority)

## Migration from global-package.json

### Step-by-Step Migration

#### Before (Deprecated Pattern)

```json
// global-package.json
{
  "name": "lib",
  "dependencies": {
    "neovim": { "version": "5.3.0", "overridden": false },
    "prettier": { "version": "3.0.0", "overridden": false },
    "typescript": { "version": "5.2.0", "overridden": false }
  }
}
```

#### After (mise Pattern)

```toml
# mise/config.toml
[tools]
"npm:neovim" = "5.3.0"
"npm:prettier" = "3.8.4"
"npm:typescript" = "5.9.3"
```

#### Migration Commands

```bash
# 1. Backup existing global packages
npm list -g --depth=0 > npm-global-backup.txt

# 2. Convert to mise.toml format (manual or scripted)
# For each package in global-package.json:
#   "package-name" → "npm:package-name" = "<verified-version>"

# 3. Add to mise/config.toml

# 4. Install via mise
mise install

# 5. Verify installation
mise ls
which prettier  # Should point to ~/.local/share/mise/installs/...

# 6. Remove old global packages (optional but recommended)
npm list -g --depth=0 --json | jq -r '.dependencies | keys[]' | xargs -I {} npm uninstall -g {}

# 7. Delete global-package.json
rm global-package.json

# 8. Update documentation
# Update any docs that reference npm install -g or global-package.json
```

### Automated Migration Script Example

```bash
#!/usr/bin/env bash
# migrate-npm-to-mise.sh

set -euo pipefail

MISE_CONFIG="${HOME}/.config/mise/config.toml"
BACKUP_FILE="npm-global-backup-$(date +%Y%m%d-%H%M%S).txt"

# Backup current global packages
echo "📦 Backing up global npm packages to ${BACKUP_FILE}..."
npm list -g --depth=0 > "${BACKUP_FILE}"

# Extract package names (exclude npm itself)
PACKAGES=$(npm list -g --depth=0 --json | jq -r '.dependencies | keys[] | select(. != "npm")')

# Generate mise config entries
echo ""
echo "📝 Generated mise.toml entries:"
echo ""
echo "# NPM Global Packages"
while IFS= read -r pkg; do
    echo "\"npm:${pkg}\" = \"<verified-version>\""
done <<< "${PACKAGES}"

echo ""
echo "⚠️  Please manually add these entries to ${MISE_CONFIG}"
echo "Then run: mise install"
```

## Tool Categories Deep Dive

### 1. Runtimes (Language Implementations)

#### Characteristics

- Provide language interpreters/compilers
- Often have ecosystem package managers (npm, pip, cargo, etc.)
- Version-sensitive for compatibility

#### Examples

```toml
[tools]
# Specific version for project compatibility
node = "<verified-version>"          # older major kept for project compatibility
python = "<verified-version>"         # Specific patch version

# Concrete current stable versions
node = "<verified-version>"
ruby = "<verified-version>"

# Version ranges (if supported)
go = "<verified-version>"               # 1.25.x line
```

#### Version Selection Strategy

- Project-local: Pin specific versions for reproducibility
- User global: Prefer concrete versions when documenting reusable setup; local rolling channels are a personal opt-in
- CI/CD: Always pin specific versions

### 2. CLI Tools (Standalone Binaries)

#### Characteristics

- Self-contained executables
- No runtime dependencies (or bundled)
- Pin concrete versions in shared configs; standalone binaries can still break scripts when their CLI changes

#### Examples

```toml
[tools]
github-cli = "<verified-version>"     # gh command
jq = "<verified-version>"              # JSON processor
ripgrep = "<verified-version>"        # Fast grep alternative
fd = "<verified-version>"             # Fast find alternative
bat = "<verified-version>"            # Cat with syntax highlighting
```

### 3. NPM Global Packages

#### Characteristics

- JavaScript packages installed globally
- Require Node.js runtime
- Often provide CLI commands

#### Examples

```toml
[tools]
# Formatters/Linters
"npm:prettier" = "<verified-version>"
"npm:eslint" = "<verified-version>"
"npm:@biomejs/biome" = "<verified-version>"

# Build Tools
"npm:typescript" = "<verified-version>"
"npm:vite" = "<verified-version>"
"npm:webpack" = "<verified-version>"

# Development Tools
"npm:nodemon" = "<verified-version>"
"npm:pm2" = "<verified-version>"
"npm:http-server" = "<verified-version>"

# Scoped Packages
"npm:@angular/cli" = "<verified-version>"
"npm:@vue/cli" = "<verified-version>"
```

#### Important Notes

- Scoped packages (starting with `@`) must include the full scope
- Package names must match npm registry exactly
- Version can be specific (`"3.0.0"`) or a controlled range (`"^3.0.0"`); prefer exact versions in shared configs and CI

### 4. Python Global Packages (via pipx)

#### Characteristics

- Python packages installed in isolated environments
- Uses `pipx` for isolation (similar to `npx`)
- Prevents dependency conflicts

#### Examples

```toml
[tools]
# Formatters/Linters
"pipx:black" = "<verified-version>"
"pipx:ruff" = "<verified-version>"
"pipx:pylint" = "<verified-version>"

# Package Management
"pipx:poetry" = "<verified-version>"
"pipx:pipenv" = "<verified-version>"

# Development Tools
"pipx:ipython" = "<verified-version>"
"pipx:jupyter" = "<verified-version>"

# Documentation
"pipx:mkdocs" = "<verified-version>"
"pipx:sphinx" = "<verified-version>"
```

#### Advantages of pipx

- Each package in isolated virtual environment
- No dependency conflicts
- Automatic binary exposure in PATH

## Integration Patterns

### Shell Integration (Zsh Example)

#### Setup in `.zshrc`

```zsh
# Activate mise
eval "$(mise activate zsh)"

# Optional: Enable completions
eval "$(mise completion zsh)"

# Optional: Set mise home
export MISE_DATA_DIR="${HOME}/.local/share/mise"
export MISE_CONFIG_DIR="${HOME}/.config/mise"
```

#### Benefits

- Automatic PATH management
- Tool shimming (fake binaries that route to mise-managed versions)
- Directory-based version switching

### Neovim Integration

#### Ensure tools are available

```toml
[tools]
# Language servers and formatters Neovim needs
"npm:typescript-language-server" = "5.1.3"
"npm:vscode-langservers-extracted" = "4.10.0"  # HTML/CSS/JSON LSP
"npm:@fsouza/prettierd" = "0.26.2"
"npm:neovim" = "5.3.0"                         # Node.js client

"pipx:python-lsp-server" = "1.14.0"
"pipx:black" = "26.1.1"
```

#### Neovim Lua Config

```lua
-- ~/.config/nvim/lua/config/mise.lua

-- Ensure mise-managed tools are in PATH
vim.env.PATH = vim.fn.expand("~/.local/share/mise/shims") .. ":" .. vim.env.PATH

-- Verify tool availability
local function check_tool(name)
  return vim.fn.executable(name) == 1
end

-- Example usage in LSP config
if check_tool("typescript-language-server") then
  require("lspconfig").tsserver.setup({})
end
```

### CI/CD Integration

#### GitHub Actions Example

```yaml
name: CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Install mise
        uses: jdx/mise-action@v2
        with:
          version: <verified-version> # Pin version for reproducibility

      - name: Install tools
        run: mise install

      - name: Verify installation
        run: mise ls

      - name: Run tests
        run: |
          # Tools installed by mise are now in PATH
          npm test
          python -m pytest
```

#### GitLab CI Example

```yaml
default:
  image: ubuntu:24.04
  before_script:
    - curl https://mise.run | sh
    - export PATH="${HOME}/.local/bin:${PATH}"
    - mise install

test:
  script:
    - mise exec -- npm test
```

## Troubleshooting

### Common Issues

#### Issue 1: Tool Not Found After Installation

### Symptoms

```bash
$ mise install
...installation succeeds...
$ which prettier
prettier not found
```

### Solutions

```bash
# 1. Verify installation
mise ls | grep prettier

# 2. Check shim exists
ls -la ~/.local/share/mise/shims/prettier

# 3. Verify PATH contains mise shims
echo $PATH | grep mise

# 4. Reload shell or reactivate mise
eval "$(mise activate zsh)"

# 5. Use mise exec explicitly
mise exec -- prettier --version
```

#### Issue 2: Version Conflict with System Tools

### Symptoms

```bash
$ which node
/usr/bin/node  # System version, not mise version

$ node --version
v14.0.0  # Old system version

$ mise current node
<verified-version>  # mise thinks it's using a different version
```

### Solutions

```bash
# 1. Check PATH order
echo $PATH
# mise shims should come FIRST

# 2. Fix PATH in shell config (.zshrc)
# Ensure mise activation is AFTER any other PATH modifications
export PATH="/usr/local/bin:$PATH"  # System paths
eval "$(mise activate zsh)"         # mise shims (should be last)

# 3. Reload shell
exec zsh

# 4. Verify
which node  # Should now point to ~/.local/share/mise/...
```

#### Issue 3: NPM Package Command Not Found

### Symptoms

```bash
$ mise install "npm:prettier"
...succeeds...
$ prettier --version
prettier: command not found
```

### Solutions

```bash
# 1. Check if binary name differs from package name
npm view prettier bin
# Output: { prettier: 'bin/prettier.cjs' }

# 2. Verify mise created shim
ls -la ~/.local/share/mise/shims/ | grep prettier

# 3. Try mise exec
mise exec -- prettier --version

# 4. Reinstall with correct package name
mise uninstall "npm:prettier"
mise install "npm:prettier@3.8.4"

# 5. For scoped packages, ensure @ is included
mise install "npm:@angular/cli"
```

#### Issue 4: `github:` backend の macOS `.app` が「壊れているため開けません」（Gatekeeper）

tar 展開が AppleDouble `._*` を実体化し codesign の resource seal を壊す（Developer ID + hardened runtime で顕在化。例: terminal-browser 0.7.x）。install/upgrade 後に bundle 内の `._*` を `find <app> -name "._*" -delete` で除去し、`codesign --verify --deep --strict` と `spctl --assess --type execute` で検証する。quarantine xattr の問題ではない。ダイアログで「ゴミ箱に入れる」を押すと本体が Trash へ移動するので、消えたら Trash 確認 → `mise uninstall`/`install` で入れ直す。

#### Issue 5: Python pipx Package Issues

### Symptoms

```bash
$ mise install "pipx:black"
Error: pipx backend not available
```

### Solutions

```bash
# 1. Ensure pipx is installed
mise install pipx

# 2. Verify pipx works
pipx --version

# 3. Reinstall package
mise install "pipx:black"

# 4. Check pipx environment
pipx list
```

### Performance Issues

#### Slow Shell Startup

### Diagnosis

```bash
# Benchmark shell startup
time zsh -i -c exit

# Profile mise activation
time eval "$(mise activate zsh)"
```

### Optimization

```zsh
# ~/.zshrc

# Option 1: Lazy load mise
if command -v mise &>/dev/null; then
    eval "$(mise activate zsh --shims)"  # Faster, only adds shims to PATH
fi

# Option 2: Cache mise activation (advanced)
MISE_CACHE="${HOME}/.cache/mise-activation.zsh"
if [[ ! -f "${MISE_CACHE}" ]] || [[ ~/.config/mise/config.toml -nt "${MISE_CACHE}" ]]; then
    mise activate zsh > "${MISE_CACHE}"
fi
source "${MISE_CACHE}"
```

## Best Practices Checklist

### Configuration

- [ ] Use `~/.config/mise/config.toml` for personal global tools
- [ ] Use project `./mise.toml` for project-specific versions
- [ ] Pin versions in projects and document any personal rolling-channel exceptions outside shared repo examples
- [ ] Group tools by category with comments
- [ ] Alphabetize within categories for maintainability

### Package Management

- [ ] Declare ALL npm packages with `"npm:"` prefix
- [ ] Declare ALL Python packages with `"pipx:"` prefix
- [ ] Remove `global-package.json` and `requirements-global.txt`
- [ ] Never use `npm install -g` or `pip install --user`
- [ ] Document any exceptions with clear rationale

### Version Control

- [ ] Commit `mise.toml` or `mise/config.toml` to git
- [ ] Add `.mise.lock` if using experimental lockfile feature
- [ ] Update `.gitignore` to exclude `node_modules/`, `venv/`, etc.
- [ ] Document tool requirements in project README

### Team Collaboration

- [ ] Onboard team with `mise install` in setup docs
- [ ] Pin critical tool versions for consistency
- [ ] Document any platform-specific tool requirements
- [ ] Include mise version in CI/CD config

### Maintenance

- [ ] Run `mise upgrade` regularly (weekly/monthly)
- [ ] Review `mise outdated` for updates
- [ ] Test updates before committing version bumps
- [ ] Keep mise itself updated: `mise self-update`

## Advanced Patterns

### Task Aliases with Tool Management

Combine tool management with task automation:

```toml
# ~/.config/mise/config.toml

[tools]
node = "24"
"npm:prettier" = "3.8.4"
"npm:eslint" = "9.39.1"

[tasks.format]
description = "Format code"
run = "prettier --write ."

[tasks.lint]
description = "Lint code"
run = "eslint ."

[tasks.format-check]
description = "Check formatting"
run = "prettier --check ."

[tasks.ci]
description = "CI pipeline"
depends = ["format-check", "lint"]
```

### Usage

```bash
mise run format      # Uses mise-managed prettier
mise run lint        # Uses mise-managed eslint
mise run ci          # Runs both checks in parallel
```

### Directory-Specific Tool Overrides

Use project-local config to override user global settings:

```toml
# ~/projects/legacy-app/mise.toml
[tools]
node = "14.21.0"  # Override global node version
"npm:typescript" = "4.9.5"  # Specific old version

# Inherits all other tools from ~/.config/mise/config.toml
```

### Conditional Tool Installation

Use mise hooks for conditional tool loading:

```toml
# mise.toml
[tools]
node = "24.16.0"
"npm:aws-cdk" = "2.1034.0"  # Only needed for AWS projects

[hooks]
# Custom hook to warn if AWS tools missing
enter = "~/.config/mise/hooks/check-aws-tools.sh"
```

```bash
#!/usr/bin/env bash
# ~/.config/mise/hooks/check-aws-tools.sh

if [[ -f "cdk.json" ]] && ! mise current "npm:aws-cdk" &>/dev/null; then
    echo "⚠️  This project uses AWS CDK. Run: mise install"
fi
```

## Related Resources

- Official Docs: <https://mise.jdx.dev>
- Tool Registry: <https://mise.jdx.dev/registry.html>
- GitHub: <https://github.com/jdx/mise>
- Community: <https://github.com/jdx/mise/discussions>

## See Also

- `best-practices.md` - Task runner best practices
- `config-templates.md` - Common configuration templates
- `current-patterns.md` - Real-world usage patterns from dotfiles
