---
name: tuxedo
description: Use when managing todo.txt tasks with the `tuxedo` CLI/TUI — adding, listing, prioritizing, completing, or archiving tasks, scripting against todo.txt with `--json`, capturing tasks from a phone or shell via the LAN capture endpoint and `inbox.txt`, or explaining tuxedo's natural-language date / recurrence syntax. Do not use for generic todo.txt format questions unrelated to tuxedo.
---

# tuxedo

tuxedo は todo.txt 形式を扱う TUI + CLI（Rust 製単一バイナリ、Homebrew tap `webstonehq/tap/tuxedo`）。`tuxedo [FILE]` で TUI、`tuxedo <command>` でワンショット実行。正本ドキュメントは https://github.com/webstonehq/tuxedo の README。

## Key facts

- コマンド一覧と引数は `tuxedo --help` が正。ここには help に書かれていない挙動だけを記す
- タスク番号は常に **1-based の物理行番号**。`list` のフィルタ・ソート表示に関わらず不変
- 対象ファイルは引数 > `TODO_FILE` > `$TODO_DIR/todo.txt` > `./todo.txt`。`DONE_FILE` 未指定時は sibling の `done.txt`
- 全 list 系コマンドは `--json` で機械可読出力（`n`, `raw`, `done`, `priority`, `projects`, `contexts`, `due`, `rec`, `t` フィールド）
- `tuxedo update` は自動更新せず、更新コマンドの案内のみ表示する

## スクリプトから使うとき

1. 対象ファイルを明示する — `TODO_DIR` / `TODO_FILE` を設定するか、カレントディレクトリの `todo.txt` を確認してから実行する
2. 読み取りは `list --json` を使い、テキスト出力をパースしない。テキストの `list` は物理行順ではなく**行全体の case-insensitive ソート順**で表示される
3. `del` は確認プロンプトで停止するため `-f` を付ける
4. `done` は完了マークのみで todo.txt に残る（todo.txt-cli と違い自動 archive しない）。done.txt へ移すには続けて `archive` を実行する
5. 変更後は `list` で行番号を取り直す — 削除・archive で行番号が詰まる

## 自然言語 add

`add` は日付・周期・優先度の自然言語をローカルのルールベースパーサで canonical 形式へ変換する（完全オフライン）。既に `due:` / `rec:` / `t:` を含む入力は変換せずそのまま保存される。

- `Buy milk tomorrow` → `Buy milk due:<翌日>`
- `Pay rent monthly on the first of the month project home` → `Pay rent +home due:<次の1日> rec:+1m`
- `Daily standup high priority` → `(A) standup rec:+1d`
- 認識語彙: 日付（today / tomorrow / 曜日 / ISO）、周期（daily / weekly / every N weeks / every business day）、`show N days before`（→ `t:`）、`project X` / `context Y`、`high|medium|low priority`

記法の意味: `rec:+1m` の `+` は前回の due 基準の厳密周期（毎月1日の家賃）、`+` 無しは完了日基準（水やり `rec:1w`）。`t:-3d` は due の3日前から表示。`note:<path>` は外部ノートへのリンク。

## TUI とスマホキャプチャ

TUI のキーバインド一覧、`s` キーで起動する LAN capture endpoint、`inbox.txt` のマージ挙動とレース条件は [references/tui-and-capture.md](references/tui-and-capture.md) を読む。CLI だけ使う場合は不要。
