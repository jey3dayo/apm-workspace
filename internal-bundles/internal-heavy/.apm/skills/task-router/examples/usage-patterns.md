# Usage Patterns - 使用パターン集

このドキュメントは、task-routerの実用的な使用パターンとベストプラクティスを提供します。

## Basic Usage - 基本的な使用

### 単純なタスク指定

最もシンプルな使い方は、自然言語でタスクを指定することです。

```bash
# コードレビュー
/task "このコードをレビューして品質を確認"

# エラー修正
/task "TypeScript型エラーを修正"

# 新機能実装
/task "ユーザー認証機能を実装"

# ドキュメント更新
/task "README.mdを更新"
```

### 期待される動作

1. タスク意図の自動分析
2. 最適なエージェントの選択
3. プロジェクトコンテキストの統合
4. エージェントによる実行

### Git/ブランチ関連

ブランチやコミットを指定したレビュー。

```bash
# ブランチレビュー
/task "origin/developでレビューして"
/task "origin/mainとの差分をレビュー"

# コミットレビュー
/task "最新のコミットをレビュー"
/task "直近3コミットをレビュー"

# ステージング
/task "ステージされた変更をレビュー"
```

### 期待される動作

1. GitHub PR意図を自動検出
2. `github-pr-reviewer` エージェントを選択
3. ブランチ/コミット情報を取得
4. 差分を分析してレビュー実行

## Advanced Usage - 高度な使用

### 複雑なマルチステップタスク

複数のステップを含むタスクを一度に指定できます。

```bash
/task "新機能を実装してテストを書いてドキュメントも更新"
```

### 実行フロー

```
Task Analysis
    ↓
Complexity: 0.92 (complex)
    ↓
Multi-Agent Strategy
    ├─ Subtask 1: "新機能を実装" → orchestrator
    ├─ Subtask 2: "テストを書く" → orchestrator
    └─ Subtask 3: "ドキュメントを更新" → docs-manager
    ↓
Sequential Execution
    ↓
Integrated Result
```

### 制約付きタスク

技術スタックや設計パターンを指定したタスク。

```bash
/task "Go言語でClean Architectureに従ってREST APIを実装"
```

### 実行フロー

```
Task Analysis
    ├─ Language: Go
    ├─ Pattern: Clean Architecture
    └─ Type: REST API
    ↓
Skill Loading
    ├─ golang skill (自動検出)
    └─ security skill (API関連)
    ↓
Agent Selection: orchestrator
    ↓
Context Enhancement
    ├─ Go イディオマティックパターン
    ├─ Clean Architecture レイヤー構造
    └─ REST API ベストプラクティス
    ↓
Implementation
```

### 分析タスク

問題の原因を調査して修正案を提示するタスク。

```bash
/task "なぜこのテストが失敗するのか原因を調査して修正案を提示"
```

### 実行フロー

```
Task Analysis
    ├─ Primary Intent: analyze (0.85)
    └─ Secondary Intent: fix (0.65)
    ↓
Agent Selection: researcher
    ↓
Investigation Phase
    ├─ テスト実行ログ分析
    ├─ コードベース調査
    └─ 根本原因特定
    ↓
Solution Phase
    ├─ 修正案の生成
    ├─ 影響範囲の評価
    └─ 実装推奨事項
```

## Semantic Analysis - セマンティック分析

### シンボル検索

特定のシンボル(クラス、メソッド、インターフェース)を検索します。

```bash
# インターフェース実装の検索
/task "AuthServiceインターフェースの全ての実装を見つけて"

# メソッド呼び出しの検索
/task "getUserByIdメソッドを呼び出している全ての場所を探して"

# クラス定義の検索
/task "Userクラスの定義と全ての使用箇所を見つけて"
```

### 実行フロー

```
Task Analysis
    ├─ Keywords: "全て", "見つけて"
    └─ Semantic Intent Detected
    ↓
Agent Selection: serena (confidence: 1.0)
    ↓
Skill Loading: semantic-analysis
    ↓
Symbol Search
    ├─ find_symbol("AuthService")
    ├─ find_referencing_symbols()
    └─ Analyze dependencies
    ↓
Result Visualization
```

### リネーム操作

シンボルをリネームし、全ての参照を更新します。

```bash
/task "UserRepositoryクラスの名前を変更して全ての参照を更新"
```

### 実行フロー

```
Semantic Analysis Detection
    ↓
Agent: serena
    ↓
Impact Analysis
    ├─ Find all references
    ├─ Check dependencies
    └─ Estimate affected files
    ↓
User Confirmation
    ↓
Rename Execution
    ├─ rename_symbol()
    └─ Update all references
    ↓
Verification
```

### 依存関係分析

コンポーネント間の依存関係を分析します。

```bash
/task "このクラスの依存関係を分析して図にして"
```

### 実行フロー

```
Agent: serena + researcher
    ↓
Dependency Tracking
    ├─ Direct dependencies
    ├─ Transitive dependencies
    └─ Circular dependencies
    ↓
Graph Generation
    ├─ Node: Classes/Modules
    ├─ Edge: Dependencies
    └─ Layers: Architecture
    ↓
Visualization (Mermaid/PlantUML)
```

## Context7 Integration - ライブラリドキュメント活用

### React Hooks

React Hooksの最新APIを使用した実装。

```bash
/task "React HooksのuseStateとuseEffectの使い方を教えて"
```

### 実行フロー

```
Library Detection: "React Hooks"
    ↓
Context7 Query
    ├─ resolve-library-id: "react"
    └─ query-docs: "useState useEffect"
    ↓
Documentation Retrieved
    ├─ useState API reference
    ├─ useEffect patterns
    └─ Best practices
    ↓
Agent: researcher (with enhanced context)
    ↓
Explanation + Code Examples
```

### Next.js App Router

Next.js 14の最新機能を使用した実装。

```bash
/task "Next.js 14のApp Routerでデータフェッチングを実装"
```

### 実行フロー

```
Library Detection: "Next.js 14", "App Router"
    ↓
Context7 Query
    ├─ resolve-library-id: "/vercel/next.js/v14"
    └─ query-docs: "App Router data fetching"
    ↓
Documentation Retrieved
    ├─ Server Components
    ├─ fetch() with cache
    └─ Loading/Error states
    ↓
Agent: orchestrator (with enhanced context)
    ↓
Implementation with latest patterns
```

### TypeScript ジェネリック

TypeScriptの高度な型システムを使用した実装。

```bash
/task "TypeScriptでジェネリック型を使った関数を実装"
```

### 実行フロー

```
Library Detection: "TypeScript", "ジェネリック"
    ↓
Context7 Query + Skill Loading
    ├─ query-docs: "TypeScript generics"
    └─ Load: typescript skill
    ↓
Enhanced Context
    ├─ Generic constraints
    ├─ Type inference
    └─ Best practices
    ↓
Agent: orchestrator
    ↓
Type-safe implementation
```

## Interactive Mode - 対話的実行

### インタラクティブモード

ユーザーとの対話を通じてタスクを実行します。

```bash
/task --interactive "複雑な問題を解決"
```

### 対話フロー

```
1. Initial Analysis
   "タスクの詳細を教えてください"

2. Clarification
   "使用する技術スタックは?"
   "制約や要件は?"

3. Execution Plan
   "以下の計画で進めます:"
   [計画の表示]
   "よろしいですか? (y/n)"

4. Step-by-step Execution
   "Step 1/3: 実行中..."
   "結果を確認しますか? (y/n)"

5. Final Review
   "完了しました。追加の変更は?"
```

### ドライラン

実際の変更なしに実行計画を確認します。

```bash
/task --dry-run "大規模リファクタリング"
```

### ドライラン出力

```markdown
## Dry Run Report

Task: "大規模リファクタリング"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Execution Plan**:

1. Analyze current structure (5 min)
2. Identify refactoring targets (10 min)
3. Create refactoring plan (15 min)
4. Execute refactoring (2 hr)
5. Run tests (20 min)
6. Update documentation (30 min)

**Affected Files** (estimated):

- src/components/\*\*/\*.tsx (45 files)
- src/hooks/\*\*/\*.ts (12 files)
- tests/\*\*/\*.test.ts (23 files)

**Estimated Risk**: Medium
**Estimated Time**: 3h 20m

**Would execute**: orchestrator → code-reviewer → error-fixer

**NOTE**: This is a dry run. No changes will be made.
```

### 詳細ログ付き実行

実行の詳細なログを表示します。

```bash
/task --verbose "パフォーマンス最適化"
```

### 詳細ログ

```
[00:00] Task Analysis Started
[00:02] Intent Detection: optimize (confidence: 0.89)
[00:03] Project Type Detected: typescript-react
[00:04] Loading Skills: typescript, react, integration-framework
[00:06] Context7 Query: react performance optimization
[00:08] Agent Selection: orchestrator (confidence: 0.92)
[00:09] Execution Plan Created
[00:10] Starting Execution Phase
[00:15] Analyzing current performance metrics...
[01:45] Identified 12 optimization opportunities
[02:30] Applying optimization 1/12: useMemo for expensive calculation
[03:15] Applying optimization 2/12: React.memo for component
...
[15:20] All optimizations applied
[15:25] Running performance tests
[16:40] Performance improved: 45% faster
[16:42] Task Completed Successfully
```

## Deep Thinking Mode - 深い思考モード

### 技術的判断が必要なタスク

複雑な技術判断が必要な場合にDeep Thinkingモードを使用します。

```bash
/task --deep-think "複雑な技術判断が必要なタスク"
/task --thinking "なぜこのエラーが発生するか調査"
```

### Deep Thinking 実行

```
🧠 Deep Thinking モードが有効になりました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Thinking Focus Areas**:

- root_cause_analysis
- design_decisions

**Analysis Phase** (Extended):

1. Surface-level analysis
   - Immediate symptoms
   - Error messages

2. Intermediate analysis
   - Related components
   - Data flow

3. Deep analysis
   - Architecture patterns
   - Design decisions
   - Trade-offs

**Execution with Deep Context**:

[Detailed reasoning process...]

**Conclusion**:

[Well-reasoned solution with rationale]
```

### 焦点領域の自動決定

タスク内容から焦点領域を自動的に決定します。

| キーワード                   | 焦点領域                  |
| ---------------------------- | ------------------------- |
| "なぜ", "原因", "理由"       | root_cause_analysis       |
| "設計", "アーキテクチャ"     | design_decisions          |
| "最適", "改善"               | optimization_strategies   |
| "実装", "方法", "アプローチ" | implementation_strategies |
| その他                       | general_analysis          |

## モード組み合わせ

複数のモードを組み合わせて使用できます。

```bash
# ドライラン + 詳細ログ
/task --dry-run --verbose "大規模変更"

# インタラクティブ + Deep Thinking
/task --interactive --deep-think "複雑な設計判断"

# 全モード
/task --interactive --dry-run --verbose --deep-think "最重要タスク"
```

## ベストプラクティス

### 1. タスクの明確化

```bash
# 良い例
/task "TypeScript型エラーを修正してテストを実行"

# 悪い例
/task "直して"  # 何を直すのか不明確
```

### 2. 制約の明示

```bash
# 良い例
/task "Go言語でREST APIを実装 (Clean Architecture)"

# 悪い例
/task "APIを作って"  # 言語や設計が不明確
```

### 3. スコープの限定

```bash
# 良い例
/task "認証モジュールのエラーハンドリングを改善"

# 悪い例
/task "全部改善して"  # スコープが広すぎる
```

### 4. 段階的実行

複雑なタスクは分割して実行します。

```bash
# Phase 1: 分析
/task "パフォーマンス問題の原因を分析"

# Phase 2: 設計
/task "パフォーマンス改善の設計を作成"

# Phase 3: 実装
/task "パフォーマンス改善を実装"
```

## トラブルシューティング

### エージェント選択が期待と異なる

```bash
# 問題: レビューを期待したがエラー修正になった
/task "コードを確認"

# 解決: より明確に指定
/task "コードレビューして品質を確認"
```

### Context7ドキュメントが取得されない

```bash
# 問題: ライブラリ名が曖昧
/task "Reactで実装"

# 解決: 具体的なライブラリと機能を指定
/task "React HooksのuseStateを使って実装"
```

### 複雑度判定が期待と異なる

```bash
# 問題: 単純タスクが複雑と判定された
/task "全ファイルをレビューして修正して最適化して"

# 解決: タスクを分割
/task "全ファイルをレビュー"
/task "レビュー結果を修正"
/task "パフォーマンスを最適化"
```

## 関連リソース

- [エラー回復戦略](error-recovery-strategies.md)
- [処理アーキテクチャ詳細](../references/processing-architecture.md)
- [エージェント選択ロジック](../references/agent-selection-logic.md)
