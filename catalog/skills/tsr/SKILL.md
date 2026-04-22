---
name: tsr
description: Use when a TypeScript or React codebase needs dead-code detection or safe unused-code removal with TSR, especially for unused exports, unused files, `.tsrignore`, and gradual cleanup workflows.
---

# TSR

## Overview

This skill is for safe dead-code cleanup in TypeScript or React projects. Start by checking configuration and running detection mode first. Do not jump directly to deletion.

Detailed config, examples, and migration notes already live in `examples/`, `README.md`, and `references/`.

## When to Use

- unused exports や unused files を整理したい
- dead code cleanup を段階的に進めたい
- `.tsrignore` を調整したい
- Next.js / React / Node 系 TS プロジェクトで false positive を減らしたい

使わない場面:

- TypeScript ではないコードベース
- 単なる duplicate code 検出
- 参照関係の可視化だけが目的

## First Pass

1. current config を確認する
2. detection mode で report を出す
3. false positive を `.tsrignore` に逃がす
4. delete は少量ずつ行う
5. verification を回す

## Minimal Workflow

```bash
node /Users/t00114/.apm/catalog/skills/tsr/config-loader.ts
pnpm tsr:check > /tmp/tsr-report.txt
pnpm tsr:fix
```

`pnpm tsr:fix` の前に、report の中身を確認すること。

## Configuration Priority

TSR config は次の順で解決される。

1. project: `.tsr-config.json`
2. home: `~/.config/tsr/config.json`
3. default: `tsr-config.default.json`

初手で設定が怪しい場合は、削除より先に `config-loader.ts` の出力を確認する。

## What to Check Before Deletion

- framework type が正しいか
- `entryPatterns` が対象を広げすぎていないか
- `.tsrignore` に framework 特有の除外が入っているか
- `maxDeletionPerRun` が大きすぎないか
- verification が有効か

## Safe Defaults

- detection first
- delete in small batches
- verify with type-check and lint
- test も必要なら config で有効化する

## Common Mistakes

- config を見ずに `--write` へ進む
- Next.js 特有ファイルを false positive のまま消す
- 一度に大量削除する
- `.tsrignore` を更新せずに report だけ見て判断する
- dead code cleanup と refactor を同じコミットに混ぜる

## Resources

- Config loader: `config-loader.ts`
- Examples: `examples/*.json`
- Config schema: `tsr-config.schema.json`
- Workflow details: `references/workflow.md`
- `.tsrignore` guide: `references/tsrignore.md`
- Migration notes: `MIGRATION.md`
