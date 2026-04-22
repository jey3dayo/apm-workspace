---
name: mcp-tools
description: Use when setting up, reviewing, or troubleshooting MCP servers, especially for config file locations, transport choices, credential handling, or startup failures.
---

# MCP Tools

## Overview

This skill is for MCP server wiring, not for using a specific downstream tool. Start by locating the real config file and deciding whether the task is setup, diagnosis, or credential review.

Read `references/mcp-tools-details.md` for fuller setup examples, `references/server-configurations.md` for server patterns, and `references/security-and-credentials.md` when secrets or token handling are in scope.

## When to Use

- MCP server を初回セットアップしたい
- 設定ファイルの場所を確認したい
- transport や command / args の書き方を見直したい
- MCP server が起動しない原因を切り分けたい
- API key や token の安全な置き場所を確認したい

使わない場面:

- 特定アプリの使い方そのものだけを知りたい
- MCP ではない一般的な CLI 導入だけをしたい

## First Pass

1. 対象が `Claude Desktop` `Codex` `他のクライアント` のどれか確定する
2. 実際に読まれる config file の場所を確認する
3. server ごとに `transport` `command/url` `args/env` を分けて確認する
4. secret を config 直書きせず、環境変数や安全な注入方法に寄せる
5. 起動失敗なら config 構文、実行コマンド、権限、依存バイナリの順で切り分ける

## Common Tasks

### Add A Server

- config file に server entry を追加する
- `stdio` なら `command` と `args` を、`http` なら `url` を確認する
- 再起動後にクライアント側の MCP server 一覧で認識を確認する

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

- 実際には別クライアントの config を編集している
- `stdio` server の失敗を network 問題だと誤認する
- `command` は正しいが依存 runtime が未インストール
- 設定確認より先に token 再発行を繰り返す

## References

- `references/mcp-tools-details.md`
- `references/server-configurations.md`
- `references/security-and-credentials.md`
