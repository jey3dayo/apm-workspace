---
name: mcp-tools
description: Use when deciding whether to install, keep, move, or remove MCP servers, or when setting up, reviewing, or troubleshooting MCP servers, especially for global vs repo-local placement, trend checks, config file locations, transport choices, credential handling, or startup failures.
---

# MCP Tools

## Overview

This skill is for MCP server selection, placement, and wiring, not for using a specific downstream tool. Start by deciding whether the task is placement review, setup, diagnosis, or credential review.

Read `references/mcp-placement.md` when deciding global vs repo-local vs on-demand placement. Read `references/mcp-tools-details.md` for fuller setup examples, `references/server-configurations.md` for server patterns, and `references/security-and-credentials.md` when secrets or token handling are in scope.

## When to Use

- MCP server を初回セットアップしたい
- MCP server を入れるべきか、消すべきか、global か repo-local か判断したい
- MCP server の流行・保守状況・代替を調べて配置を見直したい
- 設定ファイルの場所を確認したい
- transport や command / args の書き方を見直したい
- MCP server が起動しない原因を切り分けたい
- API key や token の安全な置き場所を確認したい

使わない場面:

- 特定アプリの使い方そのものだけを知りたい
- MCP ではない一般的な CLI 導入だけをしたい

## First Pass

1. 対象が `Claude Desktop` `Codex` `他のクライアント` のどれか確定する
2. 配置判断なら `global` `repo-local` `on-demand` `do-not-install` のどれかに分類する
3. 実際に読まれる config file の場所を確認する
4. server ごとに `transport` `command/url` `args/env` を分けて確認する
5. secret を config 直書きせず、環境変数や安全な注入方法に寄せる
6. 起動失敗なら config 構文、実行コマンド、権限、依存バイナリの順で切り分ける

## Common Tasks

### Add A Server

- まず `references/mcp-placement.md` で設置場所を決める
- config file に server entry を追加する
- `stdio` なら `command` と `args` を、`http` なら `url` を確認する
- 再起動後にクライアント側の MCP server 一覧で認識を確認する

### Placement Review

- current signal を見る: 公式 docs/repo、release cadence、package downloads、community mentions、known alternatives
- benefit を分類する: cross-repo foundation、project-specific tool、visual/browser tool、credentialed service、temporary investigation helper
- cost を確認する: startup fan-out、tool list noise、credentials、local process count、network dependency、diff/UI slowdown
- install/remove の前に、client、server package、transport、config source of truth、credential scope、検証方法を確定する
- performance が判断軸なら、global 維持/削除/on-demand 化の前後で startup、server status、diff UI、process count を実測する
- global に残すのは cross-repo で頻繁に使う低リスク基盤だけにする
- repo-local に寄せるのは framework/app/runtime に依存する MCP にする
- on-demand に寄せるのは重い visual/browser 操作、まれな調査、権限が強い外部サービスにする
- APM が source of truth の場合は `apm-usage` も使い、deployed target を直接編集しない

### Diagnose Startup Failure

- 実行ファイルが見つかるか
- `args` がその server に合っているか
- 必須 env が欠けていないか
- config JSON/TOML の構文が壊れていないか

### Review Credentials

- token を repo や共有 config に直書きしない
- スコープを最小にする
- 不要になった credential を放置しない

## Security Rules

- secret は最初から「漏れる前提」で最小権限にする
- ローカル開発用 token と本番用 token を分ける
- third-party server は install 前に配布元と実行コマンドを確認する
- troubleshooting 中でも秘密情報をログに出さない

## Common Mistakes

- trend だけで global に入れる
- project-specific MCP を global に常駐させる
- Codex / Claude / IDE の既存 connector と重複する MCP を追加する
- 実際には別クライアントの config を編集している
- `stdio` server の失敗を network 問題だと誤認する
- `command` は正しいが依存 runtime が未インストール
- 設定確認より先に token 再発行を繰り返す

## References

- `references/mcp-placement.md`
- `references/mcp-tools-details.md`
- `references/server-configurations.md`
- `references/security-and-credentials.md`
