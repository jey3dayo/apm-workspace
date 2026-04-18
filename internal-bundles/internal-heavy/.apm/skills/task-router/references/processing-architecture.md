# Task Processing Architecture - 4 Phase詳細フロー

このドキュメントは、task-routerスキルの4つのPhaseの詳細な処理フローを説明します。

## Phase 1: Multi-Layer Task Analysis

タスクを複数の観点から分析し、実行戦略を決定するフェーズです。

### 3層分析システム

#### 1. Semantic Layer (意味理解)

タスクの言語的意味を理解し、意図タイプを分類します。

### 9種類の意図タイプ

| 意図タイプ | 説明                 | キーワード例                     |
| ---------- | -------------------- | -------------------------------- |
| error      | エラー修正           | "エラー", "修正", "fix", "バグ"  |
| implement  | 新機能実装           | "実装", "作成", "追加", "新規"   |
| fix        | バグ修正             | "バグ", "不具合", "直す"         |
| analyze    | 分析・調査           | "分析", "調査", "なぜ", "原因"   |
| review     | コードレビュー       | "レビュー", "確認", "品質"       |
| github_pr  | GitHub PRレビュー    | "PR", "pull request", "GitHub"   |
| refactor   | リファクタリング     | "リファクタ", "改善", "整理"     |
| navigate   | コードナビゲーション | "探す", "見つける", "検索"       |
| docs       | ドキュメント操作     | "ドキュメント", "docs", "README" |

### 実装例

```python
from .shared.task_context import TaskContext
from .shared.agent_selector import analyze_task_intent

def analyze_task(task_description, options={}):
    """タスクを分析し、実行計画を作成"""

    # 統一されたタスクコンテキストの作成
    context = TaskContext(task_description, source="/task")

    # Context7統合: ライブラリ参照の検出とドキュメント強化
    if not options.get('skip_documentation'):
        detected_libraries = detect_library_references(task_description)
        if detected_libraries:
            context = enhance_context_with_docs(context, detected_libraries)

    # タスク分析レポートの生成
    report = generate_task_analysis_report(context)

    return {
        "context": context,
        "report": report,
        "execution_plan": create_execution_plan(context)
    }
```

#### 2. Intent Layer (意図分析)

主要意図と副次的意図を抽出し、確信度スコアを計算します。

### 意図抽出プロセス

1. キーワードマッチング: タスク内のキーワードを検出
2. スコアリング: 各意図タイプの確信度を計算 (0.0-1.0)
3. 主要意図決定: 最高スコアの意図を主要意図とする
4. 副次的意図抽出: 閾値以上のスコアを持つ他の意図

### スコアリングロジック

```python
def calculate_intent_scores(task_description):
    """意図スコアを計算"""

    scores = {}
    description_lower = task_description.lower()

    for intent_type, keywords in INTENT_KEYWORDS.items():
        score = 0.0
        for keyword in keywords:
            if keyword in description_lower:
                # キーワードの重要度に応じてスコア加算
                score += keyword_weight(keyword)

        # 正規化 (0.0-1.0)
        scores[intent_type] = min(score / max_score, 1.0)

    return scores
```

#### 3. Structural Layer (構造分解)

タスクを実行可能な単位に分解し、複雑度を計算します。

### 分解コンポーネント

- ターゲット: 操作対象 (ファイル、モジュール、コンポーネント)
- 制約: 実行時の制約 (技術スタック、規約、品質基準)
- スコープ: 影響範囲 (単一ファイル、モジュール、プロジェクト全体)
- 依存関係: 他のタスクやリソースへの依存

### 複雑度計算

```python
def calculate_task_complexity(components):
    """タスク複雑度を計算 (0.0-1.0)"""

    complexity_factors = {
        "targets": len(components["targets"]) * 0.15,
        "constraints": len(components["constraints"]) * 0.10,
        "scope": scope_weight(components["scope"]),  # 0.2-0.4
        "dependencies": len(components["dependencies"]) * 0.08,
        "multi_step": is_multi_step(components) * 0.2
    }

    total = sum(complexity_factors.values())
    return min(total, 1.0)
```

### 複雑度判定

- < 0.8: 単純タスク → 単一エージェント実行
- ≥ 0.8: 複雑タスク → 複数エージェント協調実行

### Task Analysis Report

```python
def generate_task_analysis_report(context):
    """タスク分析レポートを生成"""

    # ドキュメント情報のフォーマット
    doc_info = ""
    if hasattr(context, 'documentation') and context.documentation:
        doc_info = "\n📚 **Referenced Libraries**: " + ", ".join(context.documentation.keys())
        doc_info += f"\n📖 **Documentation Status**: Available ({len(context.documentation)} libraries)"

    return f"""
🎯 **Task Analysis Report**
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 **Original Request**: "{context.intent['original_request']}"
🔍 **Interpreted Intent**: {context.intent['primary']['type'] if context.intent['primary'] else 'unknown'}
🎯 **Task Category**: {get_task_category(context)}
📊 **Complexity**: {calculate_complexity(context)}
⏱️ **Estimated Time**: {estimate_time(context)}{doc_info}
🔧 **Required Capabilities**: {get_required_capabilities(context)}

**Decomposed Actions**:
{format_decomposed_actions(context)}
"""
```

## Phase 2: Dynamic Context Integration

プロジェクト情報と実行履歴を統合して最適な実行戦略を決定するフェーズです。

### コンテキスト統合フロー

```python
def integrate_dynamic_context(context):
    """動的コンテキストを統合"""

    # 1. プロジェクト情報の統合 (TaskContextに既に含まれる)
    # context.project に以下が含まれる:
    # - type: プロジェクトタイプ
    # - stack: 技術スタック
    # - structure: プロジェクト構造
    # - conventions: プロジェクトコンベンション

    # 2. 実行履歴との統合
    from .shared.task_context import enhance_context_with_history
    context = enhance_context_with_history(context, history_manager)

    # 3. 制約検証
    validate_constraints(context)

    return context
```

### プロジェクト情報

TaskContextに自動的に統合される情報。

```python
context.project = {
    "type": "typescript-react",  # プロジェクトタイプ
    "stack": ["typescript", "react", "next.js"],  # 技術スタック
    "structure": {  # プロジェクト構造
        "src": "src/",
        "tests": "tests/",
        "config": "config/"
    },
    "conventions": {  # プロジェクト規約
        "style": "airbnb",
        "testing": "jest",
        "linting": "eslint"
    }
}
```

### 実行履歴統合

類似タスクの実行履歴から推奨事項を生成します。

```python
def enhance_context_with_history(context, history_manager):
    """実行履歴でコンテキストを強化"""

    similar_tasks = history_manager.find_similar_tasks(
        context.intent['original_request'],
        context.project['type']
    )

    if similar_tasks:
        context.history = {
            "similar_count": len(similar_tasks),
            "success_rate": calculate_success_rate(similar_tasks),
            "avg_time": calculate_average_time(similar_tasks),
            "recommended_agent": find_best_performing_agent(similar_tasks)
        }

    return context
```

### 制約検証

タスクの実行可能性を検証します。

```python
def validate_constraints(context):
    """制約を検証"""

    issues = []

    # リソース制約チェック
    if requires_external_api(context) and not api_available():
        issues.append("External API not available")

    # 技術スタック互換性チェック
    if not compatible_with_stack(context, context.project['stack']):
        issues.append("Incompatible with project stack")

    # 依存関係チェック
    missing_deps = check_dependencies(context)
    if missing_deps:
        issues.append(f"Missing dependencies: {', '.join(missing_deps)}")

    if issues:
        context.validation_issues = issues
        warn_user(issues)
```

## Phase 3: Intelligent Agent Selection

確信度ベースの多段階エージェント選択を行うフェーズです。

### 選択プロセス

```python
def select_agent_for_task(context):
    """タスクに最適なエージェントを選択（必ずエージェントを選択）"""

    # 共通のエージェント選択ロジックを使用
    from .shared.agent_selector import select_optimal_agent

    selection_result = select_optimal_agent(
        context.intent['original_request'],
        context
    )

    # 実行戦略の決定（必ずエージェントベース実行）
    complexity = calculate_complexity(context)

    if complexity < 0.8:
        # 単純タスク: 単一エージェントで実行（必須）
        return {
            "strategy": "single_agent",
            "primary_agent": selection_result["agent"],
            "confidence": selection_result["confidence"],
            "reasoning": selection_result["reasoning"]
        }
    else:
        # 複雑タスク: 複数エージェントによる協調実行
        return create_multi_agent_plan(context, selection_result)
```

### 確信度スコアリング

```python
def calculate_confidence_score(intent_scores, agent_capabilities):
    """確信度スコアを計算"""

    base_score = 0.0

    # 意図スコアとエージェント能力の照合
    for intent_type, intent_score in intent_scores.items():
        if intent_type in agent_capabilities:
            capability_score = agent_capabilities[intent_type]
            base_score += intent_score * capability_score

    # 正規化 (0.0-1.0)
    normalized_score = base_score / len(intent_scores)

    # Context7調整: ドキュメントが利用可能な場合+10%
    if has_documentation():
        normalized_score *= 1.1

    return min(normalized_score, 1.0)
```

### 複数エージェント計画

複雑タスクの場合、複数エージェントによる協調実行計画を作成します。

```python
def create_multi_agent_plan(context, primary_selection):
    """複数エージェント実行計画を作成"""

    # タスクをサブタスクに分解
    subtasks = decompose_into_subtasks(context)

    # 各サブタスクにエージェントを割り当て
    agent_assignments = []
    for subtask in subtasks:
        agent = select_optimal_agent(subtask, context)
        agent_assignments.append({
            "subtask": subtask,
            "agent": agent["agent"],
            "confidence": agent["confidence"]
        })

    return {
        "strategy": "multi_agent",
        "primary_agent": primary_selection["agent"],
        "subtasks": agent_assignments,
        "confidence": calculate_overall_confidence(agent_assignments),
        "reasoning": generate_multi_agent_reasoning(agent_assignments)
    }
```

## Phase 4: Execution & Optimization

実行とリアルタイムの最適化を行うフェーズです。

### 実行フロー

```python
def execute_task(context, execution_plan):
    """タスクを実行し、最適化を行う"""

    # 実行計画の表示
    display_execution_plan(execution_plan)

    # メトリクスの初期化
    context.metrics["start_time"] = timestamp()
    context.metrics["status"] = "in_progress"

    # Context7ドキュメントの適用
    if hasattr(context, 'documentation') and context.documentation:
        from .shared.context7_integration import apply_documentation_to_task
        context = apply_documentation_to_task(context, execution_plan["primary_agent"])

    try:
        # 必ずエージェントベース実行を行う
        if execution_plan["strategy"] == "single_agent":
            result = execute_single_agent(context, execution_plan)
        else:
            result = execute_multi_agent(context, execution_plan)

        # 結果の強化
        result = enhance_result(result, context)

        # メトリクスの更新
        context.metrics["end_time"] = timestamp()
        context.metrics["status"] = "success"
        context.metrics["quality_score"] = calculate_quality_score(result)

    except Exception as e:
        # エラーハンドリングとリカバリー
        result = handle_execution_error(e, context)
        context.metrics["status"] = "partial_success" if result else "failed"

    # コンテキストの永続化
    from .shared.task_context import save_context
    save_context(context)

    return result
```

### 実行計画の表示

```python
def display_execution_plan(plan):
    """実行計画を表示"""

    # Context7情報のフォーマット
    doc_info = ""
    if plan.get('context') and hasattr(plan['context'], 'documentation'):
        docs = plan['context'].documentation
        if docs:
            doc_info = f"\n📚 **Library Docs**: {', '.join(docs.keys())}"

    print(f"""
🚀 **Task Execution Plan** (Agent-Based)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 **Strategy**: {plan['strategy']} (エージェント必須実行)
🤖 **Primary Agent**: {plan['primary_agent']}
🎯 **Confidence**: {plan['confidence']:.1%}
⏱️  **Estimated Time**: {plan.get('estimated_time', 'calculating...')}{doc_info}
""")
```

### 単一エージェント実行

```python
def execute_single_agent(context, plan):
    """単一エージェントでタスクを実行"""

    agent = plan["primary_agent"]

    # エージェントの起動
    agent_instance = initialize_agent(agent, context)

    # タスク実行
    result = agent_instance.execute(context.intent['original_request'])

    return {
        "status": "success",
        "agent": agent,
        "result": result,
        "metrics": extract_metrics(agent_instance)
    }
```

### 複数エージェント実行

```python
def execute_multi_agent(context, plan):
    """複数エージェントでタスクを協調実行"""

    results = []

    # 各サブタスクを順次実行
    for assignment in plan["subtasks"]:
        subtask = assignment["subtask"]
        agent = assignment["agent"]

        # エージェントの起動
        agent_instance = initialize_agent(agent, context)

        # サブタスク実行
        subtask_result = agent_instance.execute(subtask)

        results.append({
            "subtask": subtask,
            "agent": agent,
            "result": subtask_result
        })

    # 結果の統合
    return {
        "status": "success",
        "strategy": "multi_agent",
        "primary_agent": plan["primary_agent"],
        "subtask_results": results,
        "metrics": aggregate_metrics(results)
    }
```

### 結果の強化

```python
def enhance_result(result, context):
    """実行結果を強化"""

    # 品質スコアの計算
    quality_score = calculate_quality_score(result)

    # 推奨事項の生成
    recommendations = generate_recommendations(result, context)

    # フォローアップタスクの抽出
    follow_up_tasks = extract_follow_up_tasks(result)

    return {
        **result,
        "quality_score": quality_score,
        "recommendations": recommendations,
        "follow_up_tasks": follow_up_tasks
    }
```

### エラーハンドリング

```python
def handle_execution_error(error, context):
    """実行エラーを処理"""

    # エラータイプの分類
    error_type = classify_error(error)

    # リカバリー戦略の選択
    recovery_strategy = select_recovery_strategy(error_type, context)

    # リカバリーの試行
    if recovery_strategy:
        try:
            return recovery_strategy.execute(context)
        except Exception as recovery_error:
            log_error(recovery_error)
            return None

    return None
```

## データフロー図

```
Task Description
    ↓
[Phase 1: Analysis]
    ├─ Semantic Layer → Intent Types
    ├─ Intent Layer → Primary/Secondary Intents
    └─ Structural Layer → Complexity Score
    ↓
Task Context
    ↓
[Phase 2: Context Integration]
    ├─ Project Info → Type, Stack, Structure
    ├─ Execution History → Success Rate, Avg Time
    └─ Context7 Docs → Library Documentation
    ↓
Enhanced Context
    ↓
[Phase 3: Agent Selection]
    ├─ Intent Analysis → Agent Capabilities
    ├─ Confidence Scoring → 0.0-1.0
    └─ Strategy Decision → Single/Multi Agent
    ↓
Execution Plan
    ↓
[Phase 4: Execution]
    ├─ Agent Execution → Task Result
    ├─ Result Enhancement → Quality Score
    └─ Metrics Collection → Learning Data
    ↓
Final Result + Metrics
```

## パフォーマンス最適化

### キャッシング戦略

- プロジェクト情報: 初回ロード後にキャッシュ
- エージェント能力マトリックス: 静的キャッシュ
- Context7ドキュメント: 15分間のセルフクリーニングキャッシュ

### 並列処理

- 複数エージェント実行: 独立サブタスクを並列実行
- Context7取得: 複数ライブラリを並列取得
- メトリクス収集: 非ブロッキング収集

### リソース管理

- メモリ使用量: 最大200MB
- API呼び出し制限: レート制限の実装
- タイムアウト: デフォルト2分、調整可能
