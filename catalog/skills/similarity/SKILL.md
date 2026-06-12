---
name: similarity
description: Use when a TypeScript or JavaScript codebase needs duplicate-code detection, similar function or type-definition analysis, or refactoring-candidate triage based on `similarity-ts`. Do not use for Python, Go, Rust, or general multi-language clone detection.
---

# Similarity

`similarity-ts` で TypeScript / JavaScript の類似コードを検出し、共通化候補を優先度付けする。

## Quick Start

```bash
# ツール確認（mise 管理。見つからなければ `mise which similarity-ts` → `mise install`）
# 0.5.0 未満は interface を検出しないバグがある（下記「実測済みの落とし穴」参照）
similarity-ts -V

# 最小オプションで実行し、レポートをリポジトリ直下の tmp/ に出す
mkdir -p tmp && similarity-ts src/ > tmp/similarity-report.md

# 関数ペアが 0 件・少なすぎる場合は再実行（短い関数はスコアが割引かれるため）
similarity-ts --no-size-penalty src/ > tmp/similarity-report.md
```

初回からオプションを盛らない。結果を見てから閾値やフィルタを足す。

## Workflow

1. 対象パスでレポートを生成する。ペアがゼロ・少なすぎる場合は `--no-size-penalty` を付けて再実行する（下記「実測済みの落とし穴」参照）
2. 類似度の高いペアから読む（下表で優先度付け）
3. ペアごとに「共通化 / 保留」を判断する。実コードを読み、差分が表記揺れかビジネスロジック差かを見極める
4. 共通化するペアは参照箇所を確認し（Serena の `find_referencing_symbols` など）、テストを確保してから 1 ペアずつ抽出する
5. 完了後に同条件で再実行し、ペア数の減少を確認する

| 類似度                   | 判断                             |
| ------------------------ | -------------------------------- |
| 95%+                     | ほぼコピー。即共通化候補         |
| 90-95%                   | 高優先。差分を精査してリファクタ |
| 87-90%（デフォルト閾値） | 候補としてメモし、計画的に対応   |
| 87% 未満                 | 基本ノイズ。参考情報に留める     |

複数ペアが同じ抽出テーマに収束する場合（同型の get / remove 系など）はテーマ単位でまとめ、派生ペアを個別候補として数えない。判断と計画は生レポートと分けて `tmp/similarity-plan.md` などに書く。

計画を書く場合は references/report-analysis.md を必ず読む（実出力フォーマットの読み方と計画テンプレートがある）。

## Key Options

関数と型定義はデフォルトで両方チェックされる。クラスのみ `--classes` で明示的に有効化する。

| 目的                                          | コマンド例                                                     |
| --------------------------------------------- | -------------------------------------------------------------- |
| 閾値変更（デフォルト 0.87）                   | `similarity-ts -t 0.9 src/`                                    |
| 短い関数の重複も拾う                          | `similarity-ts --no-size-penalty src/`                         |
| 関数 / 型チェックの無効化                     | `--no-functions` / `--no-types`                                |
| interface のみ / type alias のみ              | `--interfaces-only` / `--types-only`                           |
| interface と type alias の相互比較            | `--allow-cross-kind`                                           |
| クラスチェック（デフォルト無効）              | `--classes`                                                    |
| 関数名 / 本体で絞り込み                       | `--filter-function "User"` / `--filter-function-body "prisma"` |
| 小さい関数を除外（デフォルト 3 行）           | `--min-lines 5` / `--min-tokens 50`                            |
| 類似コード本体も表示                          | `--print`                                                      |
| 拡張子指定                                    | `--extensions ts,tsx`                                          |
| 構造 / 命名の重み変更（デフォルト 0.6 / 0.4） | `--structural-weight 0.8 --naming-weight 0.2`                  |

実測済みの落とし穴:

- 関数スコアにはサイズペナルティがデフォルトで掛かり、短い関数は大きく割引かれる。5 行の完全コピーでも約 25% になり、デフォルト閾値では検出されない。短い CRUD 系の重複を探すときは `--no-size-penalty` を付ける
- v0.4.x は interface を検出しないバグがある（type alias のみ検出）。0.5.0 以降への更新はユーザーに確認してから行う。更新できない場合は、グローバル状態を変えない代替（別パスにある 0.5.0+ バイナリの直接実行など）を優先し、それも無ければ interface の重複を手動レビューで補完して、その旨をレポートに明記する

## 判断の注意

- 高類似度 ≠ 共通化すべき。ドメインが異なる（片方だけ権限チェックが増える予定など）なら重複のままが正しいことがある
- AST ベース比較のため、コメントや空白の差は無視される
- 抽象化のために `any` を導入しない。型パラメータか専用インターフェースで受ける
- 一度に大量の共通化をしない。1 ペアずつ移行し、各ステップで type-check / lint / test を通す

## 他スキルとの連携

- 重複検出を含む広いリファクタ計画（react-doctor / tsr との組み合わせ）は `refactoring` スキルが束ねる。このスキルは similarity-ts 単体の実行と判断に集中する
- ESLint・型安全性の修正は `code-quality-improvement`、デッドコード削除は `tsr` を使う
