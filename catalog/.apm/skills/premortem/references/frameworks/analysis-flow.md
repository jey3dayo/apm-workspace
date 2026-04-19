# Analysis Flow - 質問生成と選択の詳細フロー

## Overview

Premortemスキルの質問生成から選択、提示までの詳細フロー。

## Phase 1: Context Gathering（コンテキスト収集）

### 1.1 ユーザー入力の解析

```python
# 入力例
user_input = "Next.js + PostgreSQLでブログプラットフォームを構築する計画"

# 抽出する情報
- プロジェクト説明: 上記の文字列全体
- 技術スタックキーワード: "Next.js", "PostgreSQL"
- ドメインヒント: "ブログプラットフォーム" → Web開発
- 成熟度ヒント: "計画" → POC または MVP
```

### 1.2 関連ファイルの自動検出

プロジェクトディレクトリから以下を検出：

```
.kiro/steering/*.md         # プロジェクト方針
package.json                # Node.js依存関係
requirements.txt            # Python依存関係
Cargo.toml                  # Rust依存関係
README.md                   # プロジェクト概要
docs/*.md                   # ドキュメント
```

### 検出ロジック

```python
def auto_detect_files() -> List[Path]:
    files = []
    search_patterns = [
        ".kiro/steering/*.md",
        "package.json",
        "requirements.txt",
        "Cargo.toml",
        "README.md",
        "docs/*.md"
    ]
    for pattern in search_patterns:
        files.extend(glob(pattern))
    return files
```

### 1.3 ProjectContext生成

```python
context = ProjectContext(
    domain="web-development",      # ドメイン判定結果
    maturity="mvp",                # 成熟度推定
    tech_stack=["Next.js", "PostgreSQL"],  # 技術スタック抽出
    scale="medium",                # スケール判定
    description=user_input         # 元の説明
)
```

## Phase 2: Question Generation（質問生成）

### 2.1 質問プールのロード

```python
# 汎用質問（全プロジェクト共通）
generic_questions = load_yaml("references/questions/generic.yaml")  # 35問

# ドメイン別質問（web-development）
domain_questions = load_yaml("references/questions/web-development.yaml")  # 20問

# 合計: 55問の質問プール
all_questions = generic_questions + domain_questions
```

### 2.2 関連度スコアリング

各質問に対して関連度スコア（0.0-1.0）を計算：

```python
def score_question(question: Dict, context: ProjectContext) -> float:
    score = 0.0

    # 1. トリガーキーワードマッチ（最大 +0.3）
    triggers = question.get("triggers", [])
    if any(trigger in context.description.lower() for trigger in triggers):
        score += 0.3

    # 2. ドメイン適合（+0.2）
    relevance_boost = question.get("relevance_boost", {})
    if context.domain in relevance_boost.get("domains", []):
        score += 0.2

    # 3. 成熟度適合（+0.2）
    if context.maturity in relevance_boost.get("maturity", []):
        score += 0.2

    # 4. 技術スタックマッチ（最大 +0.3）
    question_text = question.get("text", "").lower()
    if any(tech.lower() in question_text for tech in context.tech_stack):
        score += 0.3

    return min(score, 1.0)
```

### スコア例

| 質問ID  | トリガー | ドメイン | 成熟度 | 技術 | 合計スコア |
| ------- | -------- | -------- | ------ | ---- | ---------- |
| WEB-001 | 0.3      | 0.2      | 0.2    | 0.0  | 0.7        |
| GEN-011 | 0.3      | 0.2      | 0.2    | 0.0  | 0.7        |
| WEB-012 | 0.0      | 0.2      | 0.2    | 0.3  | 0.7        |
| GEN-016 | 0.0      | 0.2      | 0.0    | 0.0  | 0.2        |

### 2.3 質問の選択

スコアと優先度に基づいて3-5問を選択：

```python
def select_top_questions(
    questions: List[Dict],
    context: ProjectContext,
    min_count: int = 3,
    max_count: int = 5,
    min_score: float = 0.5
) -> List[Dict]:
    # 1. スコア計算
    scored = [(q, score_question(q, context)) for q in questions]

    # 2. ソート（スコア降順、次に優先度）
    priority_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    sorted_q = sorted(
        scored,
        key=lambda x: (-x[1], priority_order.get(x[0].get("priority"), 2))
    )

    # 3. スコア閾値でフィルタ
    filtered = [q for q, s in sorted_q if s >= min_score]

    # 4. トップN問を選択
    if len(filtered) >= min_count:
        return filtered[:max_count]
    else:
        # 不足する場合は低スコアも含める
        return sorted_q[:min_count]
```

### 選択例

```
選択された質問（5問）:
1. WEB-001 (score: 0.92) - RESTful設計原則
2. GEN-011 (score: 0.88) - 認証・認可アーキテクチャ
3. WEB-012 (score: 0.85) - データベースインデックス設計
4. GEN-019 (score: 0.82) - レート制限とスロットリング
5. WEB-006 (score: 0.78) - OWASP Top 10対策
```

### 2.4 カテゴリバランス（オプション）

同じカテゴリから偏って選択されるのを防ぐ：

```python
def balance_categories(questions: List[Dict], max_per_category: int = 2) -> List[Dict]:
    category_counts = {}
    balanced = []

    for q in questions:
        category = q.get("category", "other")
        if category_counts.get(category, 0) < max_per_category:
            balanced.append(q)
            category_counts[category] = category_counts.get(category, 0) + 1

    return balanced
```

## Phase 3: Interactive Review（対話的レビュー）

### 3.1 質問の提示

各質問をマークダウン形式で1つずつ提示：

```markdown
## Q1: RESTful設計原則（Priority: Critical）

このAPIはRESTful設計原則を遵守していますか？

- リソースベースのURL設計（/users/{id}、/orders/{id}）になっていますか？
- HTTPメソッド（GET、POST、PUT、DELETE、PATCH）の使い分けは適切ですか？
- ステータスコード（200、201、400、401、404、500等）の使用は正しいですか？
- HATEOAS（Hypermedia as the Engine of Application State）は検討しましたか？

**なぜ重要か**: RESTful設計に従わないAPIは、クライアント実装が複雑になり、保守性が低下します。
```

### 3.2 回答の分析

ユーザー回答を解析し、不足概念を検出：

```python
def analyze_response(question: Dict, response: str) -> Dict:
    analysis = {
        "is_sufficient": True,
        "missing_concepts": [],
        "follow_up_needed": False
    }

    # キーワードチェック
    question_keywords = extract_keywords(question["text"])
    for keyword in question_keywords:
        if keyword not in response.lower():
            analysis["missing_concepts"].append(keyword)
            analysis["is_sufficient"] = False

    # 「わからない」「不明」等のフラグチェック
    uncertain_phrases = ["わからない", "不明", "未定", "検討中"]
    if any(phrase in response.lower() for phrase in uncertain_phrases):
        analysis["is_sufficient"] = False
        analysis["follow_up_needed"] = True

    return analysis
```

### 3.3 深堀り質問（最大2回）

不足概念が検出された場合、深堀り質問を生成：

```python
def generate_follow_up(missing_concepts: List[str], max_depth: int = 2) -> str:
    if not missing_concepts or max_depth == 0:
        return None

    # 例: "HATEOAS" が不足している場合
    if "hateoas" in [c.lower() for c in missing_concepts]:
        return """
HATEOAS（Hypermedia as the Engine of Application State）について補足します。

これはRESTの制約の1つで、APIレスポンスに「次に実行可能なアクション」のリンクを含めることです。

例:
{
  "id": 123,
  "name": "John",
  "_links": {
    "self": "/users/123",
    "orders": "/users/123/orders",
    "delete": "/users/123"
  }
}

この概念は今回のプロジェクトで必要ですか？
"""
    return None
```

### 3.4 次の質問へ遷移

全質問（5問）を順番に処理：

```python
for i, question in enumerate(selected_questions, 1):
    print(f"## Q{i}: {question['text'][:50]}...")
    response = input("回答: ")

    # 回答分析
    analysis = analyze_response(question, response)

    # 深堀り（最大2回）
    depth = 0
    while analysis["follow_up_needed"] and depth < 2:
        follow_up = generate_follow_up(analysis["missing_concepts"], max_depth=2-depth)
        if not follow_up:
            break
        print(follow_up)
        response = input("追加回答: ")
        analysis = analyze_response(question, response)
        depth += 1

    # 次の質問へ
    print("\n" + "="*60 + "\n")
```

## Phase 4: Report Generation（レポート生成）

### 4.1 盲点の分類

全ての回答を分析し、リスクレベル別に分類：

```python
def categorize_findings(questions_and_responses: List[Dict]) -> Dict:
    findings = {
        "critical": [],
        "medium": [],
        "low": [],
        "covered": []
    }

    for item in questions_and_responses:
        question = item["question"]
        response = item["response"]

        # 回答が不十分な場合
        if is_insufficient(response):
            risk_level = map_priority_to_risk(question["priority"])
            findings[risk_level].append({
                "question_id": question["id"],
                "title": extract_title(question["text"]),
                "description": question["text"],
                "recommendation": generate_recommendation(question)
            })
        else:
            findings["covered"].append({
                "question_id": question["id"],
                "title": extract_title(question["text"])
            })

    return findings
```

### 4.2 レポート整形

マークダウン形式でレポートを生成：

```markdown
# Premortem Analysis Report

**Generated**: 2026-02-13 14:30:22

## Project Context

- **Domain**: web-development
- **Maturity**: mvp
- **Scale**: medium
- **Tech Stack**: Next.js, PostgreSQL

## Critical Issues (🔴)

### 1. 認証・認可アーキテクチャの未定義

OAuth2.0、JWT、セッションベースの選択が明確ではありません。

**推奨対応**: Auth0のドキュメントを参照し、プロジェクトの要件に応じた認証方式を選定してください。

## Medium Issues (🟡)

### 2. APIレート制限の未考慮

DoS対策が計画に含まれていません。

**推奨対応**: Redis + Sliding Windowアルゴリズムの導入を検討してください。

## Already Covered (✅)

- RESTful設計原則
- データベースインデックス設計

## Recommended Actions

1. **認証方式の選定** (critical priority)
   - OAuth2.0、JWT、セッションベースの比較検討
   - Resources: https://auth0.com/docs

2. **APIレート制限の実装** (medium priority)
   - Redis + Sliding Windowの設計
   - Resources: https://redis.io/docs/manual/patterns/rate-limiter/

## Next Steps

1. 優先度の高いCritical/Medium Issuesから対応を開始してください
2. 設計ドキュメントに発見された盲点を反映してください
3. 実装開始前に再度このレポートを確認してください
```

### 4.3 セッション保存（オプション）

```python
# セッションデータをYAMLで保存
session_data = {
    "timestamp": datetime.now().isoformat(),
    "context": asdict(context),
    "questions_and_responses": questions_and_responses,
    "findings": findings
}

output_path = Path(f".premortem-sessions/{datetime.now().strftime('%Y-%m-%d-%H%M%S')}.yaml")
output_path.parent.mkdir(exist_ok=True)

with open(output_path, "w") as f:
    yaml.dump(session_data, f, allow_unicode=True)
```

## Performance Optimization

### スコアリングのキャッシュ

同じコンテキストで複数回実行する場合、スコアをキャッシュ：

```python
@lru_cache(maxsize=100)
def score_question_cached(question_id: str, context_hash: str) -> float:
    # question_id と context_hash からスコアを計算
    pass
```

### 並列処理

質問プール全体のスコアリングを並列化：

```python
from concurrent.futures import ThreadPoolExecutor

with ThreadPoolExecutor(max_workers=4) as executor:
    scores = list(executor.map(
        lambda q: score_question(q, context),
        all_questions
    ))
```

## Error Handling

```python
try:
    context = analyze_context(user_input, files)
except Exception as e:
    print(f"コンテキスト解析エラー: {e}")
    # フォールバック: デフォルトコンテキストを使用
    context = ProjectContext(
        domain="web-development",
        maturity="mvp",
        tech_stack=[],
        scale="medium",
        description=user_input
    )
```
