---
name: terminal-browser
description: >-
  `terminal-browser` CLI でターミナルペイン内に実ブラウザを開き、ページや自作 HTML を
  会話の隣に表示・操作する。「ペインでページを見せて」「作った HTML を隣に開いて」
  「terminal-browser のタブを操作して」「リモートの localhost をプレビューして」で使う。
  ヘッドレス自動化・スクレイピングは `browser-harness`、通常の Chrome 操作は
  `claude-in-chrome` を使い、本スキルは使わない。
---

# terminal-browser

`terminal-browser open <url|path>` がターミナルペインに実ブラウザ（Chromium）を出す。URL と同じ書式でローカル HTML パスも開けるので、**ページを書いて開くだけで成果物をユーザーの隣に可視化できる**。コマンドの正確な仕様は `terminal-browser --help` / `terminal-browser action --help` が正本で、ここには書き写さない。

## 基本の使い分け

- 会話の隣に見せる: `terminal-browser open --split right <url>`（`down` / `left` / `up` も可）。`--split` 無しは現在ペインを乗っ取るので、エージェントからの起動では常に `--split` を付ける
- 開いているタブの確認: `terminal-browser ls`（browser key / tab id が action の selector になる）
- タブの自動操作: `terminal-browser action -- <command>`。agent-browser 互換 CLI で、`snapshot` / `click @e14` / `fill @e3 "text"` / `eval "expr"` などを現在ターミナルタブのアクティブタブへ送る
- リモートの localhost プレビュー: `terminal-browser open --ssh <user@host> <url>`。ブラウザはローカルで動き、ネットワークリクエストだけをリモート経由にする。リモート側へ terminal-browser を直接インストールして使うのは描画が全フレーム転送になり非推奨
- ブラウザ技術でターミナルアプリを作る場合は `--app-mode`（`--preload` / `--main-script` 併用）。実例は zenbu-labs/terminal-code

## ハマりどころ

- kitty graphics protocol 対応ターミナル必須（ghostty / kitty / cmux / VSCode など）。macOS 標準 Terminal.app と Windows は不可。描画されないときはまずターミナル対応を疑う
- `action` が既存ペインでなく新規 Chrome を操作することがある（upstream issue #60）。狙いのタブに当たらないときは `terminal-browser ls` で selector を確認し、`--browser <key> --tab <id>` を明示する
- Herdr / 非 macOS Ghostty では split 関連の未修正バグが複数残っている（issues #37/#40/#48/#61）。split が壊れる環境では `--split` を諦めて専用タブで開いてもらう
- Codex sandbox 内では pane 検出に必要な内部コマンドがブロックされるため、escalated permissions で実行する（upstream の codex overlay と同旨）

## 検証への組み込み

UI 変更の確認をユーザーと共有したいとき、スクリーンショットを撮って終わりにせず、対象ページを `--split right` で開いてユーザーが直接触れる状態にする。エージェント自身の確認は `action -- snapshot` / `eval` で行い、その同じタブをユーザーも見ている状態を保つ。
