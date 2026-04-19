---
name: nvim
description: |
  [What] Specialized skill for reviewing Neovim configurations. Evaluates LSP integration, plugin management, startup performance, and Lua-based modern configuration patterns. Provides detailed assessment of lazy loading strategies, language support, AI integration, and 2025 best practices compliance
  [When] Use when: users mention "Neovim", "nvim", "editor configuration", "LSP", or work with .lua config files and Neovim settings
  [Keywords] Neovim, nvim, editor configuration, LSP
---

# Neovim Configuration Review

## Overview

Reviews Neovim configurations focusing on startup performance, LSP integration, plugin management, and modern Lua patterns. For **generic Neovim/LSP/lazy.nvim documentation**, use **Context7 MCP**:

- `/websites/neovim_io_doc` (11,916 snippets, score 81.3) - Official docs, API reference
- `/folke/lazy.nvim` (53 snippets, score 85.9) - Plugin manager usage
- `/neovim/neovim` (11,877 snippets, score 53.7) - Source code internals

This skill focuses on **dotfiles-specific patterns and review criteria**.

## Core Evaluation Areas

### 1. Startup Performance (Target: <200ms)

### Dotfiles Check

- Measure: `nvim --startuptime startup.log`, `:Lazy profile`
- Large file detection (>2MB) in `config/autocmds.lua`
- Disable providers: `vim.g.loaded_python3_provider = 0`
- Track regressions in maintenance log

### 2. LSP Integration (Target: 15+ languages)

### Dotfiles Files

- `nvim/lua/plugins/lsp.lua`: mason.nvim + mason-lspconfig
- `ensure_installed` list with `automatic_installation = true`
- pcall wrapping for error handling

### 3. Plugin Management (lazy.nvim + modular specs)

### Dotfiles Structure

- `nvim/lua/plugins/{editor,lsp,ui,git}.lua` - modular plugin specs
- Event triggers: `VeryLazy`, `BufReadPre`, `CmdlineEnter`
- Track `lazy-lock.json` in git

### 4. Lua Configuration (Complete Lua, no Vimscript)

### Dotfiles Organization

- `init.lua` → `lua/config/{lazy,options,keymaps,autocmds}.lua`
- Support `local.lua` overrides (gitignored)
- Kebab-case naming conventions

### 5. AI Integration (Supermaven/Copilot)

### Dotfiles Check

- `lua/plugins/ai.lua` or `completion.lua`
- Performance: <50ms latency (verify with profiling)
- Keybinding conflicts with space leader

## ⭐️ 5-Star Evaluation Criteria

### Startup Performance

| Rating           | Time     | Lazy Loading | Plugin Specs     | Unused Features |
| ---------------- | -------- | ------------ | ---------------- | --------------- |
| ⭐⭐⭐⭐⭐ (5/5) | <100ms   | 90%+ plugins | Precise triggers | Disabled        |
| ⭐⭐⭐⭐☆ (4/5)  | <200ms   | 70%+ plugins | Optimized        | Minimal         |
| ⭐⭐⭐☆☆ (3/5)   | <500ms   | 50%+ plugins | Basic            | Some            |
| ⭐⭐☆☆☆ (2/5)    | 500ms-1s | <50% plugins | Legacy manager   | Many            |
| ⭐☆☆☆☆ (1/5)     | >1s      | None         | Vimscript        | No optimization |

### LSP Integration Quality

- 5⭐: 15+ languages, mason auto-install, pcall wrapping, full features
- 4⭐: 10-14 languages, mason integration, basic error handling
- 3⭐: 5-9 languages, manual setup, partial features
- 2⭐: <5 languages, manual installation, basic setup
- 1⭐: No LSP or broken configuration

### Plugin Ecosystem Health

- 5⭐: lazy.nvim, 90%+ event/cmd/ft triggers, lock file tracked
- 4⭐: lazy.nvim, 70%+ lazy-loaded, documented
- 3⭐: packer, 50%+ lazy-loaded, some docs
- 2⭐: vim-plug, minimal lazy loading, no docs
- 1⭐: Legacy manager, no lazy loading

### 2025 Best Practices

- 5⭐: Complete Lua, lazy.nvim, mason LSP, AI integration
- 4⭐: Complete Lua, lazy.nvim, mason LSP
- 3⭐: Mostly Lua, modern plugin manager
- 2⭐: Mixed Lua/Vimscript, legacy manager
- 1⭐: Vimscript-based configuration

## Review Workflow (Dotfiles-Specific)

1. Measure: `nvim --startuptime`, `:Lazy profile`
2. Structure: `init.lua` → `lua/config/` → `lua/plugins/`
3. Plugins: Count, check `lazy-lock.json`, verify event triggers
4. LSP: `lua/plugins/lsp.lua` mason setup, 15+ languages
5. Keybindings: Space leader, no conflicts
6. AI: `lua/plugins/ai.lua`, <50ms latency
7. Performance: `docs/performance.md` targets
8. Health: `:checkhealth` for providers/LSP
9. Standards: Lua-only, lazy.nvim, LSP-native, AI integration

## Dotfiles-Specific Patterns

### File Organization

```
nvim/
├── init.lua                    # Entry point
├── lazy-lock.json              # Plugin versions (tracked in git)
├── lua/
│   ├── config/                 # Core configuration
│   │   ├── lazy.lua            # lazy.nvim bootstrap
│   │   ├── options.lua         # vim.opt settings
│   │   ├── keymaps.lua         # Global keybindings
│   │   └── autocmds.lua        # Autocommands (large file detection)
│   ├── plugins/                # Plugin specifications
│   │   ├── editor.lua          # Editor plugins (treesitter, autopairs)
│   │   ├── lsp.lua             # LSP configuration (mason, lspconfig)
│   │   ├── ui.lua              # UI plugins (telescope, nvim-tree)
│   │   └── git.lua             # Git plugins (gitsigns, fugitive)
│   └── utils/                  # Utility functions
└── local.lua                   # Machine-specific overrides (gitignored)
```

### Performance Benchmarks (from docs/performance.md)

- Startup time: <200ms (ideal <100ms)
- First edit: <300ms from nvim command
- LSP attach: <500ms for most languages
- Plugin load: 90%+ lazy-loaded

### Cross-Tool Integration

Check consistency with:

- WezTerm: Gruvbox theme, Nerd Font compatibility
- Zsh: Shared FZF keybindings, environment variables
- Git: Editor integration (git commit, git rebase)

Refer to `.claude/rules/tools/` for cross-tool patterns.

## Common Issues & Quick Fixes

| Issue                 | Dotfiles Solution                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------ |
| Startup >500ms        | Check unused providers, lazy loading specs, large file detection                           |
| Legacy plugin manager | Migrate to lazy.nvim (`nvim/lua/config/lazy.lua`), track `lazy-lock.json`                  |
| <10 LSP languages     | Configure `ensure_installed` in `lua/plugins/lsp.lua` with `automatic_installation = true` |
| Missing lazy loading  | Add event/cmd/ft triggers to plugin specs                                                  |
| Provider errors       | Disable in init.lua: `vim.g.loaded_python3_provider = 0`                                   |

## Context7 Integration Examples

### For generic questions, query Context7 first

```
# Neovim API usage
Query: "How to configure autocommands in Neovim"
Library: /websites/neovim_io_doc

# Lazy.nvim patterns
Query: "How to lazy load plugins on specific events"
Library: /folke/lazy.nvim

# LSP setup
Query: "How to setup language servers with nvim-lspconfig"
Library: /neovim/neovim
```

### Then apply to dotfiles

```lua
-- Query Context7 for API details, then apply to dotfiles structure
vim.keymap.set('n', '<leader>ff', '<cmd>Telescope find_files<cr>', { desc = 'Find files' })
```

## 🤖 Agent Integration

### Code-Reviewer Agent

- 提供: ⭐️5段階評価、Dotfiles構造評価、lazy loading検証、AI統合評価
- タイミング: Neovim設定レビュー時

### Orchestrator Agent

- 提供: 設定最適化計画、プラグイン選定、パフォーマンス改善
- タイミング: 設定改善・最適化時

### Error-Fixer Agent

- 提供: 設定エラー診断、プラグイン競合解決、Lua構文修正
- タイミング: 起動エラー・プラグインエラー時

### 自動ロード条件

- "Neovim"、"nvim"、"editor configuration"、"LSP"に言及
- .luaファイル（Neovim設定）操作時
- init.lua、lua/配下のファイル操作時

## Integration with Related Skills

- code-review: 全体的な品質評価フレームワーク
- typescript: TypeScript LSP設定レビュー
- semantic-analysis: プラグイン依存関係分析
- dotfiles-integration: クロスツール連携（Gruvbox、ターミナル統合）

## Reference Material

### Context7 Libraries

- `/websites/neovim_io_doc` - Official docs
- `/folke/lazy.nvim` - Plugin manager
- `/neovim/neovim` - Source code

### Dotfiles Docs

- `.claude/rules/tools/nvim.md` - Neovim-specific rules
- `docs/performance.md` - Performance benchmarks
- `docs/tools/nvim.md` - Setup and maintenance
