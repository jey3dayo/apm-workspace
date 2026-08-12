# tuxedo TUI keybindings と capture endpoint

出典: GitHub README（https://github.com/webstonehq/tuxedo）と実測（tuxedo 2026.7.1）。TUI 内では `?` でヘルプが出るため、迷ったらそちらが正。

## Keybindings

| 分類            | キー                                                                                                                                                                                                  |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 移動            | `j`/`↓` 次、`k`/`↑` 前、`gg` 先頭、`G` 末尾、`Ctrl-d`/`Ctrl-u` 半ページ                                                                                                                               |
| 編集            | `n` 追加（自然言語パーサ）、`e` Normal 編集、`i` Insert 編集、`x` 完了トグル、`dd` 削除、`p` 優先度サイクル(A→B→C→無)、`c` context、`+` project、`yy` 行コピー、`yb` 本文のみコピー、`u` undo（50段） |
| フィルタ/ソート | `/` 検索、`fp` project 絞込、`fc` context 絞込、`ff` 保存済みフィルタ、`fs` 検索を保存、`S` ソート切替（priority→due→file order）、`v` visual 選択、`space` 行トグル                                  |
| 表示            | `l` リスト表示、`a` archive ビュー、`A` 完了タスクを done.txt へ移動、`H` 完了タスク表示切替、`o`/`O` note を開く/作成、`[`/`]` サイドバー、`T` テーマ、`D` 密度、`L` 行番号                          |
| システム        | `:`/`Ctrl-P` コマンドパレット、`s` 共有 QR、`?` ヘルプ、`,` 設定、`q` 終了                                                                                                                            |

- 2キーチョード（`gg` `dd` `yy` `yb` `fp` `fc` `ff` `fs`）は **600ms 以内**に入力する
- カスタムキーバインドは `${XDG_CONFIG_HOME:-~/.config}/tuxedo/keybinds.toml` の `[normal]` セクション。ただし `begin_prompt_project` は再割当不可（`+` がパーサの modifier 区切りと衝突するため）

## Capture endpoint（`s` キー）と inbox.txt

- `s` で LAN 上に capture サーバーが起動し QR を表示。スマホでスキャンすると Add 画面の PWA が開く
- キャプチャは todo.txt に直接書かれず、sibling の **`inbox.txt`** に着地する
- `inbox.txt` は TUI の外部変更ポーリング時（アイドル時約 250ms）にドレインされる: 各行が `n` と同じ自然言語パーサを通り、作成日が付与され、1回の undo 可能バッチとして todo.txt にマージされる（`u` で一括ロールバック可）
- TUI を起動していない間はドレインされない。汎用エンドポイントなので shell / iOS Shortcuts / cron からの append も producer になれる:

  ```sh
  echo "Refill prescription tomorrow" >> ~/notes/inbox.txt
  ```

### サーバーの挙動と注意

- 初回 `s` で bind しセッション中は起動し続ける。以後の `s` は QR 再表示のみ。ポートは OS 割り当てで `config.toml` に永続化
- 保護ルートは 64 文字 hex トークン（`config.toml` の `share_token`）でゲート。**平文 HTTP** のため信頼できるネットワーク限定。漏洩時は `share_token` を削除して `s` を再押下するとローテーションされる
- capture サーバー自体は TUI と同じアドバイザリロックを取りクラッシュセーフ（中断された staging は次回起動時にリプレイ）。**単純な shell append はロックを取らない**ため、capture サーバーの書き込みと厳密に直列化したい場合はサーバー経由にする
- 自動アップデートチェックは `$XDG_CACHE_HOME/tuxedo/latest_version.json` に 24h キャッシュ、`TUXEDO_NO_UPDATE_CHECK=1` で無効化
