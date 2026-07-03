# Herdr config.toml リファレンス

herdr 0.7.x 時点の設定面の要約。網羅ではなく、ここにない項目は https://herdr.dev/docs/configuration/ を取得して確認する。

## トップレベル

```toml
onboarding = false   # 初回セットアップ画面をスキップ
```

## [update]

```toml
[update]
channel = "stable"      # "preview" で開発ブランチのビルドを herdr update で取得（Homebrew/mise/Nix 経由は無視される）
version_check = true    # バックグラウンドの新バージョン確認
manifest_check = true   # agent-detection manifest のリモート確認
```

## [terminal]

```toml
[terminal]
default_shell = "nu"    # 新規ペインの実行ファイル名/パス。未設定時は $SHELL → /bin/sh
shell_mode = "auto"     # auto=macOSでlogin shell / "login" / "non_login"
new_cwd = "follow"      # follow=元ペインを継承 / "home" / "current" / 固定パス "~/Projects"
```

既存ペインは再作成まで現行シェルを維持する。command pane は `/bin/sh -c` 経由のまま。

## [worktrees]

```toml
[worktrees]
directory = "~/.herdr/worktrees"   # sidebar からの git worktree checkout 先。<directory>/<repo>/<branch-slug>
```

## [remote]

```toml
[remote]
manage_ssh_config = true   # herdr --remote 用に keepalive fallback 付き一時 SSH config を生成。自前の keepalive 設定が優先される
```

## [keys]

prefix デフォルトは `ctrl+b`。主なアクションフィールド:

| 分類               | フィールド                                                                                                                                                                   |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 全般               | `prefix`, `detach`, `goto`, `workspace_picker`, `copy_mode`, `resize_mode`, `zoom`, `toggle_sidebar`, `open_notification_target`                                             |
| workspace          | `new_workspace`, `rename_workspace`, `close_workspace`, `previous_workspace`, `next_workspace`, `switch_workspace`(1..9), `new_worktree`, `open_worktree`, `remove_worktree` |
| tab                | `new_tab`, `next_tab`, `previous_tab`, `switch_tab`(1..9), `rename_tab`, `close_tab`                                                                                         |
| pane               | `focus_pane_left/down/up/right`, `swap_pane_left/down/up/right`, `cycle_pane_next`, `cycle_pane_previous`, `last_pane`, `split_vertical`, `split_horizontal`, `close_pane`   |
| navigate-mode 専用 | `navigate_workspace_up/down`, `navigate_pane_left/down/up/right`（プレーンキー可、`prefix+` 不可）                                                                           |
| agent              | `previous_agent`, `next_agent`, `focus_agent`(1..9)                                                                                                                          |
| remote             | `remote_image_paste`（`herdr --remote` 時のみ有効。`""` で無効化）                                                                                                           |

- optional アクション（`previous_workspace`, `last_pane`, `open_worktree` など）はデフォルト未設定
- navigate-mode ショートカットと一般アクションが同じキーのとき、navigate mode 中は navigate 側が勝つ
- left/right 矢印は pane-left/right navigation の恒久エイリアス
- Alt / Cmd / 修飾付き記号の到達性は端末や tmux の設定に依存する

## [[keys.command]]

```toml
[[keys.command]]
key = "prefix+alt+g"
type = "pane"                  # "pane" | "shell" | "plugin_action"
command = "lazygit"            # plugin_action のときは action id（重複時は qualified id "example.layout.apply"）
description = "run lazygit"    # 省略可。prefix+? ヘルプパネルの表示名
```

- `pane`: 一時ペインで実行し、終了時にペインを閉じる
- `shell`: バックグラウンドで detached 実行（`/bin/sh -lc` 経由）
- 渡される環境変数: `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`, `HERDR_ACTIVE_WORKSPACE_ID`, `HERDR_ACTIVE_TAB_ID`, `HERDR_ACTIVE_PANE_ID`, `HERDR_ACTIVE_PANE_CWD`
- shell command はフォーカス中ペインの cwd から実行される（検出できた場合）

## [theme]

```toml
[theme]
name = "catppuccin"
auto_switch = false        # true で端末の light/dark 通知に追従
light_name = "catppuccin-latte"   # 省略時は組込みの sibling を自動選択
dark_name = "catppuccin"
```

組込みテーマ: `catppuccin`, `catppuccin-latte`, `terminal`, `tokyo-night`, `tokyo-night-day`, `dracula`, `nord`, `gruvbox`, `gruvbox-light`, `one-dark`, `one-light`, `solarized`, `solarized-light`, `kanagawa`, `kanagawa-lotus`, `rose-pine`, `rose-pine-dawn`, `vesper`。`terminal` はホスト端末の ANSI パレットに追従。

```toml
[theme.custom]           # 個別色の上書き
panel_bg = "reset"       # hex / 色名 / rgb(r,g,b) / reset・default・none・transparent
accent = "#a6e3a1"
```

## [ui]

```toml
[ui]
sidebar_width = 32
sidebar_min_width = 18
sidebar_max_width = 36
mobile_width_threshold = 64          # この幅以下でモバイル1カラムレイアウト
mouse_capture = true                 # false で端末側にクリックを渡す（Cmd+クリックURL等）
right_click_passthrough_modifier = "" # "ctrl" 等。shift は不可
redraw_on_focus_gained = true
mouse_scroll_lines = 3
confirm_close = true                 # workspace close 時の確認
prompt_new_tab_name = true           # 新規タブでラベル入力を求める
pane_borders = true
pane_gaps = true
show_agent_labels_on_pane_borders = false
agent_panel_sort = "spaces"          # "spaces" | "priority"（blocked→done→working→idle→unknown）
accent = "cyan"
```

## [ui.toast]（ポップアップ通知）

```toml
[ui.toast]
delivery = "off"        # off(デフォルト) | herdr | terminal | system
delay_seconds = 1       # 0–3600。finished/needs-input 通知の遅延（遅延後も同状態のときだけ通知）

[ui.toast.herdr]
position = "bottom-right"   # top-left / top-right / bottom-left / bottom-right

[ui.toast.clipboard]
enabled = true
position = "bottom-center"  # top/bottom × left/center/right
```

- `terminal`: 端末のエスケープシーケンスでデスクトップ通知（Ghostty, iTerm2, Kitty, WezTerm）。SSH 越しに有用
- `system`: macOS は `terminal-notifier` → `osascript`、Linux は `notify-send`
- アクティブタブへの通知は抑制される（background attention 用）

## [ui.sound]

```toml
[ui.sound]
enabled = true                       # デフォルト有効。ローカルクライアントが再生
path = "sounds/notification.mp3"     # 全通知音。mp3 のみ。相対パスは config ファイル基準
done_path = "sounds/done.mp3"        # finished のみ上書き
request_path = "sounds/request.mp3"  # needs-input のみ上書き

[ui.sound.agents]                    # per-agent: "default" | "on" | "off"
droid = "off"                        # droid はデフォルトでミュート
claude = "on"
```

macOS は `afplay`、Linux は `paplay`→`pw-play`→`ffplay`→`mpg123`→`mpv` の順で試行。`HERDR_DISABLE_SOUND` で強制無効化。

## [advanced]

```toml
[advanced]
scrollback_limit_bytes = 10485760   # 新規ペインのスクロールバック。既存ペインは再作成まで据え置き
```

alternate screen のアプリ（vim, htop 等）はスクロールバックを生成しない。

## [session]

```toml
[session]
resume_agents_on_restore = true   # デフォルト有効。サーバー再起動後に対応 agent をネイティブセッションで再開
```

対応: Claude Code, Codex, Cursor Agent CLI, GitHub Copilot CLI, Droid, Kimi Code CLI, Qoder CLI, Pi, Hermes Agent, OpenCode, Kilo Code CLI。

## [experimental]

```toml
[experimental]
pane_history = false        # ペイン内容をサーバー再起動越しに保存（secrets を含みうるためデフォルト off）
allow_nested = false        # herdr in herdr（テスト用のみ）
kitty_graphics = false
reveal_hidden_cursor_for_cjk_ime = false   # macOS IME の候補ウィンドウ追従用にカーソル anchor を露出
cjk_ime_agents = []         # allow-list（空=全ペイン）。"claude", "codex", "pi" 等
cjk_ime_cursor_shape = "steady_block"      # block / steady_block / underline / steady_underline / bar / steady_bar
switch_ascii_input_source_in_prefix = false  # macOS のみ。prefix mode 中に ASCII 入力ソースへ切替
```

CJK IME 利用者（日本語入力）は `reveal_hidden_cursor_for_cjk_ime` + `cjk_ime_agents` と `switch_ascii_input_source_in_prefix` が実用上重要。

## 環境変数

| 変数                  | 用途                                       |
| --------------------- | ------------------------------------------ |
| `HERDR_CONFIG_PATH`   | config ファイルパスの上書き                |
| `HERDR_SESSION`       | CLI コマンドの対象セッション選択           |
| `HERDR_SOCKET_PATH`   | ソケットパスの低レベル上書き               |
| `HERDR_LOG`           | ログフィルタ（例 `HERDR_LOG=herdr=debug`） |
| `HERDR_DISABLE_SOUND` | サウンド再生の強制無効化                   |

## ログ

`~/.config/herdr/herdr.log`, `herdr-client.log`, `herdr-server.log`（自動ローテーション）。config warning の確認は server log。
