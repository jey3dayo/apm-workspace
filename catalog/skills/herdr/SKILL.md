---
name: herdr
description: Use when creating or editing herdr configuration (`~/.config/herdr/config.toml`) — keybindings, themes, UI/sidebar, notifications, sounds, terminal defaults, worktrees, or experimental options — or when herdr shows a startup config warning. Do not use for generic terminal multiplexer comparisons.
---

# Herdr Configuration

herdr は tmux 風 prefix モードを持つ agent-multiplexer TUI。設定は単一の TOML ファイルで管理する。

## Key facts

- 設定ファイル: `~/.config/herdr/config.toml`（`HERDR_CONFIG_PATH` で上書き可）
- デフォルト全設定の出力: `herdr --default-config`
- 反映: `herdr server reload-config`（再起動不要。startup-only 設定のみ再起動が必要）
- 不正な値は安全なデフォルトに fallback し、startup warning が出る。warning は `~/.config/herdr/herdr-server.log` で確認する
- キーバインドをデフォルト（v2）へ戻す: `herdr config reset-keys`（config.toml をバックアップして `[keys]` / `[[keys.command]]` を除去）

## Workflow

1. 既存 config を読む — `~/.config/herdr/config.toml` を必ず先に読む。コメントに書かれた規約（prefix 選定、Ghostty 互換バインド、JIS キーボードの `¥` 扱いなど）はユーザーの設計判断であり、編集時に必ず維持する。
2. 設定項目を確認する — 対象セクションの仕様は [references/configuration.md](references/configuration.md) を参照。載っていない項目・挙動が疑わしい項目は https://herdr.dev/docs/configuration/ の現行ドキュメントを取得して確認する（herdr はバージョンで設定面が変わる。`herdr --version` で確認）。
3. 編集する — 既存のセクション順・コメントスタイルを保って編集する。新規作成時は `herdr --default-config` を起点にせず、ユーザーが求めた項目だけを書く（herdr は未指定項目をデフォルトで補う）。
4. 反映と検証 — `herdr server reload-config` を実行し、`herdr-server.log` の末尾に新しい config warning が出ていないことを確認して完了。warning が出た場合は該当値を修正して再実行する。

## Keybinding safety rules

キーバインドは prefix-first が原則。直接ショートカットはシェルや TUI から入力を奪う。

- `prefix+n` = prefix を押してから `n`。`ctrl+alt+n` = 直接ショートカット。プレーンな印字キー単独（`"n"` など）は入力を横取りするため禁止 — 意図的な直接バインド以外は必ず `prefix+` を付ける
- 例外: `navigate_workspace_*` / `navigate_pane_*` は navigate-mode 専用でプレーンキー可（`j`, `k` など）。ただし `prefix+`, `esc`, `enter`, `tab`, `shift+tab`, `left`, `right`, 無修飾 `1`–`9` は使えない
- 1つのアクションに複数キーを配列で割当可: `next_tab = ["prefix+n", "ctrl+alt+]"]`
- インデックスバインドは `1..9` 表記: `switch_tab = "prefix+1..9"`（legacy `[keys.indexed]` は使わない）
- バインドを外すときは空文字列 `""` を代入する
- デフォルトキーを別アクションに割り当てるときは、元のアクションの退避先を検討する（例: `prefix+o` を `cycle_pane_next` に使うなら `open_notification_target` を別キーへ）

キー文字列は `ctrl+a` / `shift+n` / `alt+1` / `cmd+k`、特殊キー `enter` `tab` `esc` `left` 等、名前付き記号 `minus` `comma` `plus` `backtick` 等を受け付ける。JIS キーボードの `¥` は shift なしで U+00A5 を送るため、`|` ではなく `¥` そのものでバインドする。

## Custom command keybindings

```toml
[[keys.command]]
key = "prefix+alt+g"
type = "pane"        # pane=一時ペインで実行 / shell=バックグラウンド / plugin_action=プラグイン action id
command = "lazygit"
description = "run lazygit"   # prefix+? のヘルプパネルに表示される
```

コマンドには `HERDR_SOCKET_PATH`, `HERDR_ACTIVE_PANE_CWD` などの環境変数が渡る。詳細は references/configuration.md。
