# Analysis Flow - 質問選択と分析の詳細ルール

質問生成から選択、深掘り、レポート生成までの判断ルール。スコアリングの実装は `scripts/analyze_context.py` が正となる。

## Phase 1: Context Gathering

ユーザー入力とリポジトリから `ProjectContext`（domain / maturity / tech_stack / scale / description / evidence）を組み立てる。優先順位と注意点は `SKILL.md` の Context Gathering / Context Model を参照。

抽出例:

```text
入力: "Next.js + PostgreSQL でブログプラットフォームを構築する計画"
→ tech_stack: [Next.js, PostgreSQL]
→ domain: web-development（キーワードマッチ）
→ maturity: poc または mvp（"計画" から推定、断定しない）
```

## Phase 2: Question Selection

### スコアリング基準

各質問の関連度（0.0-1.0）は以下の加点で決める:

| 観点                                | 加点 |
| ----------------------------------- | ---- |
| トリガーキーワードが入力にマッチ    | +0.3 |
| ドメインが `relevance_boost` に一致 | +0.2 |
| 成熟度が `relevance_boost` に一致   | +0.2 |
| 技術スタックが質問本文にマッチ      | +0.3 |

### 選択ルール

1. スコア降順、同点なら priority（critical > high > medium > low）でソート
2. スコア 0.5 以上から上位 3-5 問を選択。足りない場合は低スコアも含めて最低 3 問
3. 同一カテゴリは原則 2 問まで（プロジェクトがそのカテゴリに明確に偏っている場合を除く）
4. 選択後、`SKILL.md` の Context-Specific Risk Lenses と照らし、プロジェクト形状に合うリスクが漏れていれば差し替える

## Phase 3: Interactive Review（interactive モードのみ）

1 問ずつ提示し、回答ごとに:

1. 回答に含まれない概念（質問の箇条書きで触れた項目）を特定する
2. 「わからない」「未定」「検討中」が含まれる場合は深掘り対象とする
3. 深掘り質問は 1 問につき最大 2 回。概念の簡単な説明を添えて、プロジェクトでの要否を聞く
4. 深掘りが尽きたら次の質問へ進む

全質問の完了後、またはユーザーが打ち切りを求めた時点でレポートを生成する。

## Phase 4: Report Generation

`SKILL.md` の Output Contract に従う。分類とSeverityのルールは Gap Classification を参照。

- 回答や証拠から判断できないものは `Missing` / `Needs Clarification` とし、証拠を捏造しない
- `Covered` の項目も省略せず記載する（レビューの再現性のため）
- Recommended next action は Recommended Action Rules に従い、小さく割り当て可能な単位にする

### セッション保存（オプション）

ユーザーが結果の保存を求めた場合は `tmp/premortem/` 配下に保存する。形式は `references/examples/*.yaml` を参照。
