---
name: herdr
description: Use when creating or editing herdr configuration (`~/.config/herdr/config.toml`) — keybindings, themes, sidebar rows, tab-bar status, window title, notifications, sounds, terminal defaults, worktrees, or experimental options — when `herdr config check` or a startup warning reports a config problem, or when inspecting or controlling live Herdr workspaces, tabs, panes, and agents through the CLI. Do not use for generic terminal multiplexer comparisons.
---

# Herdr Configuration and Runtime Control

herdr は tmux 風 prefix モードを持つ agent runtime。設定は単一の TOML ファイルで管理し、live workspace / tab / pane / agent は socket API の CLI helper で操作する。

**設定編集はこのスキルが正本。runtime 操作のコマンド仕様は binary 同梱の `herdr --skill` が正本**（下記「Runtime control」参照）。

## Key facts

- 設定ファイル: `~/.config/herdr/config.toml`（Windows は `%APPDATA%\herdr\config.toml`。`HERDR_CONFIG_PATH` で上書き可）
- デフォルト全設定の出力: `herdr --default-config`（コメント付き。インストール済み version の実体なので docs より優先する）
- 検証: `herdr config check` — 未知キー、型不一致、無効な sidebar トークン、存在しないサウンドファイルを報告する。正常時は `config: ok`。`HERDR_CONFIG_PATH=<候補ファイル> herdr config check` で本番 config を触らずに素案を通せる
- version: `herdr --version` / 更新は `herdr update`。stable の最新は `curl -fsSL https://herdr.dev/llms.txt` の `Current stable release:` 行
- 反映: `herdr server reload-config`（再起動不要。startup-only 設定のみ再起動が必要）
- 不正な値は安全なデフォルトに fallback し、startup warning が出る。warning は `~/.config/herdr/herdr-server.log` で確認する
- キーバインドをデフォルト（v2）へ戻す: `herdr config reset-keys`（config.toml をバックアップして `[keys]` / `[[keys.command]]` を除去）
- client / server で所属が分かれる: theme・sidebar レイアウト・copy 挙動・keybindings は **client** のローカル config、pane defaults・worktrees・integrations・custom command は **pane が動く server** の config

## Configuration workflow

1. 既存 config を読む — `~/.config/herdr/config.toml` を必ず先に読む。コメントに書かれた規約（prefix 選定、Ghostty 互換バインド、JIS キーボードの `¥` 扱いなど）はユーザーの設計判断であり、編集時に必ず維持する。
2. 設定項目を確認する — 対象セクションの要約は [references/configuration.md](references/configuration.md)（基準は stable 0.9.0）。そこに無い項目・挙動が疑わしい項目は推測せず、次の順で一次情報を引く。

   ```bash
   herdr --version                        # 手元の binary
   curl -fsSL https://herdr.dev/llms.txt  # 現在の stable version と version 固定の一次情報索引
   ```

   キーの型・デフォルト・許容値・説明は **機械可読な config-reference JSON が正本**。全文を読み込まず jq でキー指定して引く（コマンド形は references/configuration.md 冒頭）。構造の解説とレシピが要るときだけ https://herdr.dev/docs/configuration/ を取得する。

   **手元の binary が stable より古いことがある。** references/configuration.md は古い binary で通らない項目に「〈version〉では未対応」と注記してある。該当したら回避策を書くのではなく、まず `herdr update` で上げられないかユーザーに確認する。

3. 編集する — 既存のセクション順・コメントスタイルを保って編集する。新規作成時は `herdr --default-config` を丸ごと写さず、ユーザーが求めた項目だけを書く（herdr は未指定項目をデフォルトで補う）。
4. 反映と検証 — `herdr config check` で `config: ok` を確認してから `herdr server reload-config` を実行し、`herdr-server.log` の末尾に新しい config warning が出ていないことを確認して完了。warning が出た場合は該当値を修正して再実行する。

## Keybinding safety rules

キーバインドは prefix-first が原則。直接ショートカットはシェルや TUI から入力を奪う。

- `prefix+n` = prefix を押してから `n`。`ctrl+alt+n` = 直接ショートカット。プレーンな印字キー単独（`"n"` など）は入力を横取りするため禁止 — 意図的な直接バインド以外は必ず `prefix+` を付ける
- 直接バインドを足すなら `ctrl+alt` 系が最も安全。主要ターミナルと GNOME / KDE のデフォルトを避けた family として公式に推奨されている。prefix バインドを残したまま配列で併記する形にする
- 例外: `navigate_workspace_*` / `navigate_pane_*` は navigate-mode 専用でプレーンキー可（`j`, `k` など）。ただし `prefix+`, `esc`, `enter`, `tab`, `shift+tab`, `left`, `right`, 無修飾 `1`–`9` は使えない
- 1つのアクションに複数キーを配列で割当可: `next_tab = ["prefix+n", "ctrl+alt+]"]`
- インデックスバインドは `1..9` 表記: `switch_tab = "prefix+1..9"`（legacy `[keys.indexed]` は互換のため parse されるが新規 config では使わない）
- バインドを外すときは空文字列 `""` を代入する
- デフォルトキーを別アクションに割り当てるときは、元のアクションの退避先を検討する（例: `prefix+o` を `cycle_pane_next` に使うなら `open_notification_target` を別キーへ）
- copy mode 中も設定した prefix は prefix として効く。デフォルト `ctrl+b` のままだと copy mode の page-up が使えないので、`ctrl+b` を page-up に使いたいなら prefix を別キーにする

キー文字列は `ctrl+a` / `shift+n` / `alt+1` / `cmd+k`、特殊キー `enter` `tab` `esc` `left` 等、名前付き記号 `minus` `comma` `ampersand` `plus` `backtick` 等を受け付ける。JIS キーボードの `¥` は shift なしで U+00A5 を送るため、`|` ではなく `¥` そのものでバインドする。

## Custom command keybindings

```toml
[[keys.command]]
key = "prefix+alt+g"
type = "popup"       # popup / pane / shell / plugin_action
command = "lazygit"
description = "run lazygit"   # prefix+? のヘルプパネルに表示される
width = "80%"                 # popup のみ。セル数 or "80%"。省略で半分サイズ
height = "80%"
```

- `popup`: tab レイアウトを変えずに session-modal な popup で実行。Esc も含め入力を全部取る。**ad-hoc なシェルやレビュー TUI にはこれが第一候補**。`HERDR_PANE_ID` は渡らないので `HERDR_ACTIVE_PANE_ID` を使う
- `pane`: 一時的な zoom pane で実行し、終了時に閉じる
- `shell`: バックグラウンドで detached 実行（Unix は `/bin/sh -lc`）
- `plugin_action`: インストール済みプラグインの action id（重複時は qualified id `example.layout.apply`）

渡される環境変数: `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`, `HERDR_ACTIVE_WORKSPACE_ID`, `HERDR_ACTIVE_TAB_ID`, `HERDR_ACTIVE_PANE_ID`, `HERDR_ACTIVE_PANE_CWD`。詳細は references/configuration.md。

## Runtime control

**コマンド仕様は binary が正本。runtime 操作をする前に `herdr --skill` を実行してその内容に従う。** ID の形、`agent start` / `agent prompt` / `pane wait-output` の契約、read source の選び方などをこのスキルへ写さないのは、version 差でずれるため。`herdr --skill` は binary 同梱なのでインストール済み version と必ず一致する（docs サイトは stable より先を追っているので一致しない）。

herdr の一部の出力は「Herdr skill が既に context にあるなら `herdr --skill` は SKIP」と案内するが、**このスキルには当たらない。本スキルは config と運用規約だけを持ち、runtime のコマンド契約は意図的に持たない**ので、runtime 操作をするなら `herdr --skill` は必ず取得する。

version 依存の詳細が要るときは `herdr <group>`（例 `herdr pane`, `herdr agent`）で group ヘルプを出す。bare `herdr` は TUI を起動するので discovery に使わない。

前提: `HERDR_ENV=1` が立っている pane の中にいること。立っていなければ Herdr 外なので runtime 操作はしない（config 編集は Herdr 外でも可）。

### House rules（このスキル固有の運用規約）

- server を勝手に再起動しない。client / server の互換エラーで操作できない場合も `herdr status` の結果と失敗したコマンドを報告して確認を取る。`herdr server stop` / main プロセスの kill も同様
- 自分が作っていない workspace / tab / pane / session を閉じない。
- ユーザーが明示しない限り新しい workspace / tab / worktree / cwd を作らない。「ペインを作って」は既定で自分と同じ tab の sibling pane（`herdr pane split --current`）として解釈する
- 背景作業は `--no-focus`。ユーザーがコンテキストを切り替えたいと言ったときだけ focus する
- ID は JSON レスポンスから読む。sidebar の並び順や「3 タブ目」といった表示位置から推測しない。ユーザーが表示順で指定したら label と表示順を照合し、raw `number` が workspace 内の連番だと仮定しない
- 読み戻していないプロセス名を報告に書かない。pane にコマンドを起動したら `herdr pane process-info --pane <pane_id>` で cwd と foreground process を読み戻し、報告には pane_id + workspace label + 絶対 cwd + 実際に読み戻したプロセスを併記する
- shell が待機中の pane にだけコマンドを起動する。agent や別 TUI が動作中なら上書きせず、別 pane の選択・作成またはユーザー確認へ切り替える
- `hunk diff` や `lazygit` などの interactive TUI は agent 自身の PTY ではなく、ユーザーが見る Herdr pane で起動する
