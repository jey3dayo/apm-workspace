# Detailed Mode 実行ガイド

包括的な品質評価を実施する詳細モードの実行方法を定義します。

## 概要

Detailed Mode は、⭐️5段階評価体系を用いて複数の次元から総合的にコードを評価します。プロジェクトタイプを自動検出し、利用可能な技術スタック別スキルや reference を組み合わせて、文脈に即したレビューを行います。

## 実行フロー

### Step 1: オプションと制約の確認

- 詳細モードの前提を確認する
  - `--with-impact`, `--deep-analysis`, `--verify-spec` は optional
  - 利用可能な semantic tooling が無ければ、その旨を明示して通常の詳細レビューにフォールバックする
- レビューのために git 状態は変更しない
- dirty worktree でもレビューを続行する

### Step 2: 対象ファイル決定

対象指定は次の優先順で確定する。

1. `--staged`
2. `--recent`
3. `--branch <name>`
4. フラグ未指定時は staged changes
5. 次に previous commit diff
6. 次に primary development branch との差分
7. 最後に最近変更された reviewable files

primary development branch は、明示指定が無ければ remote の default branch、次に `main`、最後に `master` の順で解決する。

対象から除外する代表例:

- build artifact
- generated file
- minified asset
- vendor / cache / lockfile

reviewable files は、人が保守する source / config / test / 関連度の高い docs を指す。

レビュー対象の決定結果は、根拠と件数を冒頭で必ず示す。

### Step 3: プロジェクト分析

次を確認して、どの観点を強めるかを決める。

- プロジェクト種別
  - Next.js / React SPA / TypeScript Node.js / Go API / Generic
- 技術スタック
  - `package.json`, `tsconfig.json`, `go.mod`, CI 設定、テスト配置
- 構造
  - clean architecture, layered, fullstack, library
- テストの有無
- CI の有無

プロジェクト判定の基本ルールは `config/default-projects.json` を参照する。

### Step 4: 技術スタック別観点の統合

- 利用可能な skill があれば読む
  - 例: `typescript`, `react`, `golang`
- 未導入の skill 名が project config に出てきても、それだけで停止しない
- 不足している skill は、`references/tech-stack-skills.md` と `config/default-projects.json` を根拠に観点へ還元して扱う
  - 例: `security` が無くても入力検証・認証・秘密情報管理はレビューする
  - 例: `clean-architecture` が無くても依存方向と責務分離はレビューする

### Step 5: 評価基準の統合

評価基準は次の順に組み立てる。

1. `references/evaluation-framework.md`
2. `config/default-projects.json` の project-specific weight / guideline 情報
3. 利用可能なら stack-specific skill
4. プロジェクト固有ガイドライン
   - `./.claude/review-guidelines.md`
   - `./docs/review-guidelines.md`
   - `./docs/guides/review-guidelines.md`

存在しないファイルや未導入 skill を前提にしないこと。欠けている場合は、その source を単に除外して継続する。

### Step 6: 包括的レビュー実行

レビュー時は次を必ず含める。

- 冒頭に対象決定方法と対象件数
- findings first
- 各指摘に `file:line`
- 各評価次元の星評価
- 優先度付きアクションプラン
- no findings の場合はその明記

`--with-impact` が有効かつ semantic tooling が利用可能な場合のみ、次を追加する。

- 変更シンボルの一覧
- 参照元または影響範囲
- breaking change の有無

利用不可能なら「impact 分析は環境制約により未実施」と短く書いて通常レビューを続行する。

### Step 7: 結果のまとめ方

```markdown
## 総合評価

- Overall Quality: ⭐️⭐️⭐️⭐️☆
- Risk Level: Medium
- Recommendation: Approve with minor changes

## 主な指摘

- findings を severity 順で列挙

## 次元別評価

- コード品質
- セキュリティ
- パフォーマンス
- テスト
- エラーハンドリング
- アーキテクチャ

## 優先度付きアクションプラン

- 高
- 中
- 低
```

### Step 8: PR コメント自動チェック

レビュー結果出力後、`--no-comments` が指定されていなければ PR コメントチェックを実行する。詳細は `references/pr-comment-integration.md` を参照。
