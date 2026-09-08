# Herdr config.toml リファレンス

**基準は stable 0.9.0。** 「0.8.2 では未対応」と注記した項目だけが古い binary で通らない。

- 現在の stable version と version 固定の一次情報の索引: `curl -fsSL https://herdr.dev/llms.txt`（先頭に `Current stable release:` が出る）
- 全設定キーの型・デフォルト・許容値・説明は機械可読な JSON が正本。全文を読み込まず jq でキー指定して引く:

  ```bash
  V=0.9.0   # llms.txt の Current stable release
  curl -fsSL "https://raw.githubusercontent.com/herdrdev/herdr/v$V/docs/next/website/src/data/config-reference.json" \
    | jq --arg key 'ui.sidebar_width' '.sections[].keys[] | select(.key == $key)'
  ```

  セクション一覧は `jq -r '.sections[] | "\(.title) (\(.keys|length))"'`、あるキーの前方一致は `select(.key|startswith("ui.sidebar"))`。

- 構造の解説とレシピ（人間向け HTML）: https://herdr.dev/docs/configuration/
- インストール済み binary の実体: `herdr --default-config`（version は `herdr --version`）

**手元の binary が stable より古いことがある。**書いたら必ず `herdr config check` を通す — 未知キー、型不一致、無効な sidebar トークン、存在しないサウンドファイルをすべて報告してくれる。`HERDR_CONFIG_PATH=<候補ファイル> herdr config check` で本番 config を触らず素案を検証できる。

## トップレベル

```toml
onboarding = false   # 初回セットアップ画面をスキップ（未設定 or true で表示）
```

## [server]

```toml
[server]
headless_cols = 120   # client 未接続時の仮想端末サイズ（layout と新規 pane に使われる）
headless_rows = 40
```

client が 1 つ接続すると全 tab はそのサイズに追従する。複数 client では tab ごとに「最後に触った client」のサイズになる。全 client が detach すると既存 PTY は最後のサイズを保持し、新規 layout は上記 fallback を使う。

## [update]

```toml
[update]
channel = "stable"      # "preview" で開発ビルドを herdr update で取得（Homebrew/mise/Nix 経由は無視）
version_check = true    # バックグラウンドの新バージョン確認
manifest_check = true   # agent-detection manifest のリモート確認
```

`herdr channel show` / `herdr channel set <stable|preview>` でも操作できる。

## [terminal]

```toml
[terminal]
default_shell = "nu"    # 新規ペインの実行ファイル名/パス。未設定時は $SHELL → /bin/sh（Windows は PowerShell）
shell_mode = "auto"     # auto=macOS で login shell / "login" / "non_login"
new_cwd = "follow"      # follow=元ペイン/workspace を継承 / "home" / "current" / 固定パス "~/Projects"
kitty_graphics = true   # pane 画像描画と pane graphics API。デフォルト有効
```

- 既存ペインは再作成まで現行シェルを維持する。command pane は `/bin/sh -c`、detached は `/bin/sh -lc` 経由のまま（Windows は `cmd.exe /d /c`）
- `new_cwd` に対して CLI / socket API の明示 `--cwd` が優先される
- `[terminal] kitty_graphics` が正で、legacy `[experimental] kitty_graphics` も互換のため受理される（両方あれば `terminal` 側が勝つ）。**0.8.2 では `[terminal]` 側が未対応**なので `[experimental]` に書く。変更には server 再起動または client の再 attach が必要
- remote では server 側の設定が pane graphics の解析と API 可用性を、client 側の設定が外側端末への出力を決める

## [worktrees]

```toml
[worktrees]
directory = "~/.herdr/worktrees"   # sidebar からの git worktree checkout 先。<directory>/<repo>/<branch-slug>
```

sidebar の worktree アクションは既存ローカルブランチがあれば checkout、無ければ作成し、source workspace 配下にグループ化した新 workspace として開く。親 workspace を閉じてもチェックアウトフォルダとブランチは消えない。削除は子 workspace の `Delete worktree checkout...`（`git worktree remove`。ブランチは削除しない）。CLI からは `herdr worktree list|create|open|remove`。

## [remote]

```toml
[remote]
manage_ssh_config = true   # herdr --remote 用に keepalive fallback 付き一時 SSH config を生成。自前の keepalive 設定が優先される
```

Linux / macOS では per-attach の OpenSSH control socket で最初の認証済み接続を再利用する（Windows OpenSSH は非対応）。

## [keys]

prefix デフォルトは `ctrl+b`。主なアクションフィールド:

| 分類               | フィールド                                                                                                                                                                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 全般               | `prefix`, `help`, `settings`, `detach`, `reload_config`, `goto`, `workspace_picker`, `copy_mode`, `resize_mode`, `zoom`, `toggle_sidebar`, `open_notification_target`                                                                          |
| workspace          | `new_workspace`, `rename_workspace`, `close_workspace`, `previous_workspace`, `next_workspace`, `switch_workspace`(1..9), `new_worktree`, `open_worktree`, `remove_worktree`                                                                   |
| tab                | `new_tab`, `next_tab`, `previous_tab`, `switch_tab`(1..9), `rename_tab`, `close_tab`, `move_tab_previous`, `move_tab_next`                                                                                                                     |
| pane               | `focus_pane_left/down/up/right`, `swap_pane_left/down/up/right`, `resize_pane_left/down/up/right`, `cycle_pane_next`, `cycle_pane_previous`, `last_pane`, `split_vertical`, `split_horizontal`, `close_pane`, `rename_pane`, `edit_scrollback` |
| navigate-mode 専用 | `navigate_workspace_up/down`, `navigate_pane_left/down/up/right`（プレーンキー可、`prefix+` 不可）                                                                                                                                             |
| agent              | `previous_agent`, `next_agent`, `focus_agent`(1..9)                                                                                                                                                                                            |
| remote             | `remote_image_paste`（`herdr --remote` 時のみ有効。`""` で無効化）                                                                                                                                                                             |

- optional アクション（`previous_workspace`, `last_pane`, `open_worktree`, `move_tab_*`, `resize_pane_*` など）はデフォルト未設定
- `resize_pane_*` は resize mode に入らずに一発でリサイズする直接バインド用（例 `"ctrl+shift+alt+left"`）
- navigate-mode ショートカットと一般アクションが同じキーのとき、navigate mode 中は navigate 側が勝つ
- left/right 矢印は pane-left/right navigation の恒久エイリアス
- Alt / Cmd / 修飾付き記号の到達性は端末や tmux の設定に依存する。直接バインドを足すなら `ctrl+alt` family が最も衝突しにくい
- legacy `[keys.indexed]`（`tabs` / `workspaces` / `agents`）は互換のため parse されるが、新規 config では `switch_tab` / `switch_workspace` / `focus_agent` を使う

## [[keys.command]]

```toml
[[keys.command]]
key = "prefix+alt+g"
type = "popup"                 # "popup" | "pane" | "shell" | "plugin_action"
command = "lazygit"            # plugin_action のときは action id（重複時は qualified id "example.layout.apply"）
description = "run lazygit"    # 省略可。prefix+? ヘルプパネルの表示名（既定は 'custom command'）
width = "80%"                  # popup のみ。セル数 or パーセント文字列。省略で半分サイズ
height = "80%"
```

- `popup`: tab レイアウトを変えない session-modal popup。終了まで Esc を含む全入力を受け取る。border 込みのサイズで、最小値未満は clamp される。`HERDR_PANE_ID` は渡らないので `HERDR_ACTIVE_PANE_ID` を使う。`command = "exec \"${SHELL:-sh}\""` で ad-hoc ターミナルになる
- `pane`: 一時的な zoom pane で実行し、終了時にペインを閉じる
- `shell`: バックグラウンドで detached 実行（`/bin/sh -lc` 経由）
- 渡される環境変数: `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`, `HERDR_ACTIVE_WORKSPACE_ID`, `HERDR_ACTIVE_TAB_ID`, `HERDR_ACTIVE_PANE_ID`, `HERDR_ACTIVE_PANE_CWD`
- shell command はフォーカス中ペインの cwd から実行される（検出できた場合）

## [theme]

```toml
[theme]
name = "catppuccin"
auto_switch = false              # true で端末の light/dark 通知に追従
light_name = "catppuccin-latte"  # 省略時は組込みの sibling を自動選択
dark_name = "catppuccin"
```

組込みテーマ: `catppuccin`, `catppuccin-latte`, `terminal`, `tokyo-night`, `tokyo-night-day`, `dracula`, `nord`, `gruvbox`, `gruvbox-light`, `one-dark`, `one-light`, `solarized`, `solarized-light`, `kanagawa`, `kanagawa-lotus`, `rose-pine`, `rose-pine-dawn`, `vesper`。`terminal` はホスト端末の ANSI パレットに追従。Settings で手動選択すると `auto_switch` は無効化される。

```toml
[theme.custom]           # 個別色の上書き
panel_bg = "reset"       # hex / 色名 / rgb(r,g,b) / reset・default・none・transparent
accent = "#a6e3a1"
sidebar_bg = "#181825"   # 省略時 sidebar はホスト端末背景のまま
active_row_bg = "#1e1e2e"  # active Space / focused Agent 行の背景
selection_bg = "#313244"   # navigate-mode のカーソル行背景

[theme.custom.light]     # auto_switch = true のときだけ上乗せされる mode 別サブテーブル
panel_bg = "#eff1f5"
text = "#4c4f69"
[theme.custom.dark]
panel_bg = "#1e1e2e"
text = "#cdd6f4"
```

適用順: 組込みテーマ → `[theme.custom]` → `[theme.custom.light]` / `[theme.custom.dark]`。mode 別サブテーブルは **0.8.2 では未対応**（`unknown config key`）。

色トークンは `accent`, `panel_bg`, `sidebar_bg`, `active_row_bg`, `selection_bg`, `text`, `subtext0`, `surface0/1`, `surface_dim`, `overlay0/1`, `mauve`, `green`, `yellow`, `red`, `blue`, `teal`, `peach` など。全一覧は config-reference JSON を `startswith("theme.custom")` で引く。

## [ui]

```toml
[ui]
sidebar_width = 26
sidebar_min_width = 18
sidebar_max_width = 36
sidebar_start_collapsed = false       # 次回起動から反映
sidebar_collapsed_mode = "compact"    # "compact"=細い status rail / "hidden"=幅ゼロ
mobile_width_threshold = 64           # この幅以下でモバイル1カラムレイアウト
mouse_capture = true                  # false で端末側にクリックを渡す（Cmd+クリックURL等）
copy_on_select = true                 # false でドラッグ選択を保持し ctrl+c / cmd+c まで copy しない
host_cursor = "auto"                  # "auto" | "native" | "drawn"（Windows/WSL では drawn が既定挙動）
right_click_passthrough_modifier = "" # "ctrl" 等。shift は不可
redraw_on_focus_gained = true
mouse_scroll_lines = 3
confirm_close = true                  # workspace close 時の確認
prompt_new_tab_name = true            # 新規タブでラベル入力を求める
prompt_new_workspace_name = false
pane_borders = "auto"                 # "auto"(split のみ) | "always"(単一 pane も枠) | "off"。legacy boolean も parse される（true=auto / false=off）。0.8.2 は boolean のみ
pane_outer_borders = true             # pane 領域の外周。always で単一 pane を囲むには必須
pane_scrollbars = true
pane_gaps = true
show_agent_labels_on_pane_borders = false
hide_tab_bar_when_single_tab = false
tab_bar_position = "top"              # "top" | "bottom"
tab_bar_right_separator = " "
window_title = "{hostname}: {workspace}"
agent_panel_sort = "spaces"           # "spaces"（= "workspaces"）| "priority"（blocked→done→working→idle→unknown）
status_indicators = "dots"            # "dots" | "symbols"（形でも状態を区別）
accent = "cyan"
```

### window_title

Herdr は pane 内の `OSC 0`/`OSC 2` を止めるので、外側端末のタイトルは Herdr が書く。トークン: `{hostname}`, `{workspace}`, `{tab}`, `{pane}`（focused pane の手動名）, `{terminal_title}`（focused pane 自身のタイトル、spinner 除去済み）。`{{` `}}` はリテラル波括弧。**server 側でレンダリングされる**ので `{hostname}` は pane が動くマシン名になる。`""` で外側端末のタイトルを触らない。

### tab_bar_right（tmux 風ステータス）

```toml
[ui]
tab_bar_right = [
  { type = "zoom" },
  { type = "hostname" },
  { type = "datetime", format = "%H:%M" },
  { type = "text", text = "prod" },
  { type = "command", command = "~/.config/herdr/status.sh", interval_seconds = 5, timeout_seconds = 2 },
]
tab_bar_right_separator = " · "
```

デフォルトは空。`hostname` / `datetime` / `command` は server 側で解決されるので `herdr --remote` ではリモートの値になる。`datetime` は strftime だが UTC offset / Unix timestamp 系（`%z`, `%s`）は拒否される。`command` は即時実行 → `interval_seconds` 間隔（1〜31,536,000）、`timeout_seconds` は 1〜3,600。成功時は最終行のみ採用、ESC シーケンスは解釈せず除去、失敗・空出力・timeout でエントリをクリア。区切りは可視エントリ間だけに入る。

### [ui.sidebar.agents] / [ui.sidebar.spaces]

```toml
[ui.sidebar.agents]
row_gap = 0    # エントリ間の空行。1 で以前の間隔
rows = [
  ["state_icon", "machine", "workspace", "tab"],
  ["agent"],
]

[ui.sidebar.spaces]
row_gap = 0
rows = [
  ["state_icon", "workspace"],
  ["branch", "git_status"],
]

[ui.sidebar.agents.rows_by_agent]   # canonical agent ID（case-sensitive、alias 不可）
claude = [["state_icon", "workspace", "tab"], ["terminal_title_stripped"], ["agent"]]
```

- Agent トークン: `state_icon`, `state_text`, `machine`, `workspace`, `tab`, `pane`, `agent`, `terminal_title`, `terminal_title_stripped`, `$name`（pane metadata）。`machine` は複数マシン接続時のみ表示され、**0.8.2 では未対応**
- Space トークン: `state_icon`, `state_text`, `workspace`, `branch`, `git_status`, `$name`（workspace metadata）
- 値の無いトークンと区切りは消え、全トークンが空の行は消える。1 layout あたり最大 16 行 × 各行最大 16 トークン
- `rows_by_agent` は `rows` を**置換**する（追加ではない）
- トークンは inline style table にできる: `{ token = "workspace", fg = "#89b4fa", bold = true, dim = false }`。`fg` は厳密な `#RGB` / `#RRGGBB`。省略フィールドは文脈デフォルトを維持し、明示 `false` は modifier を外す
- text 系トークンは最大 16 個の順序付き `rules` を取れる。各 rule は `equals` / `contains` / `starts_with` / `gt` / `lt` のいずれか 1 つ + `fg` / `bold` / `dim`。最初にマッチした rule が勝ち、指定フィールドのみ上書きする。文字列条件は case-sensitive（`ignore_case = true` で ASCII のみ大小無視）、`gt` / `lt` は有限数値のみで完全一致 parse が必要。`state_icon` と composite の `git_status` は固定 style のみ。**0.8.2 では未対応**（`RawSidebarToken` の parse error）

  ```toml
  rows = [
    ["state_icon", "workspace", "tab"],
    [{ token = "machine", fg = "#fff", rules = [{ equals = "Local", fg = "#f55" }] }, "agent"],
    [{ token = "$load", fg = "#fff", rules = [{ gt = 80, fg = "#f55", bold = true }, { gt = 50, fg = "#fc0" }] }],
  ]
  ```

- `$name` の値は `herdr pane report-metadata <pane_id> --source <id> --token model=opus` / `herdr workspace report-metadata` で報告する。style はローカル config 側が持つ
- sidebar 行設定は展開状態のデスクトップ sidebar のみに効く（collapsed / mobile は固定レイアウト）

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
- `system`: macOS は `terminal-notifier` → `/usr/bin/osascript`（fallback は Script Editor 名義で表示され、クリックで端末を前面化できない）。Linux は `notify-send`
- アクティブタブへの通知は抑制される（background attention 用）
- CLI から任意の通知を出すには `herdr notification show <title> [--body TEXT] [--position ...] [--sound none|done|request]`

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

キーは canonical agent id で、実行ファイル名と一致しないものがある: `open_code`（OpenCode）, `github_copilot`（Copilot CLI）。他は `pi`, `claude`, `codex`, `gemini`, `cursor`, `devin`, `agy`, `cline`, `kimi`, `kiro`, `droid`, `amp`, `grok`, `hermes`, `kilo`, `qodercli`, `qwen`, `maki`, `muse`。

macOS は `afplay`、Linux は `paplay`→`pw-play`→`ffplay`→`mpg123`→`mpv` の順で試行。`HERDR_DISABLE_SOUND` で強制無効化。

## [advanced]

```toml
[advanced]
scrollback_limit_bytes = 10000000   # 新規ペインのスクロールバック。既存ペインは再作成まで据え置き
```

alternate screen のアプリ（vim, htop 等）はスクロールバックを生成しない。

## [session]

```toml
[session]
resume_agents_on_restore = true   # デフォルト有効。サーバー再起動後に対応 agent をネイティブセッションで再開
```

official integration が session ref を報告している pane のみ再開でき、他は通常のシェルとして復元される。integration の導入は `herdr integration install <agent>` / 状態は `herdr integration status`。

## [experimental]

```toml
[experimental]
pane_history = false        # ペイン内容をサーバー再起動越しに保存（secrets を含みうるためデフォルト off）
allow_nested = false        # herdr in herdr（テスト用のみ）
reveal_hidden_cursor_for_cjk_ime = false   # macOS IME の候補ウィンドウ追従用にカーソル anchor を露出
cjk_ime_agents = []         # allow-list（空=全ペイン）。"claude", "codex", "pi" 等
cjk_ime_cursor_shape = "steady_block"      # block / steady_block / underline / steady_underline / bar / steady_bar
switch_ascii_input_source_in_prefix = false  # macOS/Windows。prefix mode 中に ASCII 入力ソースへ切替
# kitty_graphics            # legacy。[terminal] kitty_graphics が正（0.8.2 のみここに書く）
```

CJK IME 利用者（日本語入力）は `reveal_hidden_cursor_for_cjk_ime` + `cjk_ime_agents` と `switch_ascii_input_source_in_prefix` が実用上重要。

## 環境変数

| 変数                      | 用途                                                                                                |
| ------------------------- | --------------------------------------------------------------------------------------------------- |
| `HERDR_CONFIG_PATH`       | config ファイルパスの上書き                                                                         |
| `HERDR_SESSION`           | CLI コマンドの対象セッション選択                                                                    |
| `HERDR_SOCKET_PATH`       | ソケットパスの低レベル上書き                                                                        |
| `HERDR_PROCESS_DETECTION` | Linux の foreground 検出戦略: `native`（既定）/ `child-groups`（opt-in、server 側・再起動要）       |
| `HERDR_AGENT`             | sandbox / wrapper 越しに動く agent の manifest を明示（例 `HERDR_AGENT=claude nono run -- claude`） |
| `HERDR_LOG`               | ログフィルタ（例 `HERDR_LOG=herdr=debug`）                                                          |
| `HERDR_DISABLE_SOUND`     | サウンド再生の強制無効化                                                                            |

pane 内には `HERDR_ENV=1`, `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_PANE_ID`, `HERDR_BIN_PATH`, `HERDR_SOCKET_PATH` が注入される。

## agent detection のローカル上書き

`~/.config/herdr/agent-detection/<agent>.toml` を置くとローカル override が常に勝つ。無い場合は cached remote manifest と bundled manifest の新しい方が使われる。`herdr server update-agent-manifests` で即時取得＋reload、手編集後は `herdr server reload-agent-manifests`。状態の説明は `herdr agent explain <target>`。

## ログ

`~/.config/herdr/herdr.log`, `herdr-client.log`, `herdr-server.log`（自動ローテーション）。config warning の確認は server log。
