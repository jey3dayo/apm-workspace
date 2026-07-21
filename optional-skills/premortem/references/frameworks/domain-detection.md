# Domain Detection

プロジェクトのドメインを判定するためのキーワード対応表。判定の実装は `scripts/analyze_context.py` の `DOMAIN_PATTERNS` が正となる。

## Detection Keywords

| Domain          | Keywords                                                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| web-development | `react`, `vue`, `angular`, `svelte`, `node.js`, `express`, `django`, `flask`, `rails`, `api`, `rest`, `graphql` |
| mobile-apps     | `ios`, `swift`, `swiftui`, `android`, `kotlin`, `react-native`, `flutter`, `mobile`, `app`                      |
| data-systems    | `spark`, `hadoop`, `flink`, `kafka`, `etl`, `pipeline`, `warehouse`, `bigquery`, `redshift`, `snowflake`        |
| infrastructure  | `kubernetes`, `docker`, `terraform`, `ansible`, `aws`, `gcp`, `azure`, `devops`, `deployment`                   |
| security        | `security`, `encryption`, `oauth`, `jwt`, `iam`, `rbac`, `penetration`, `vulnerability`, `compliance`           |
| ai-ml           | `llm`, `gpt`, `claude`, `rag`, `embedding`, `prompt`, `fine-tuning`, `pytorch`, `machine learning`, `inference` |

## Examples

- "Next.js + PostgreSQL でブログプラットフォームを構築" → `web-development`
- "Flutter でクロスプラットフォームアプリを開発" → `mobile-apps`
- "Spark を使った ETL パイプライン構築" → `data-systems`
- "Terraform で AWS インフラを構築" → `infrastructure`
- "OAuth2.0 を使った認証基盤" → `security`
- "RAG を使った社内ドキュメント検索チャットボット" → `ai-ml`

## Fallback Strategy

- 複数ドメインに該当: キーワードマッチ数が最も多いドメインを選択
- どのドメインにも該当しない: `web-development` を既定値とする（最も一般的なユースケースのため）
- 複数ドメインが拮抗する場合は、ユーザー入力やリポジトリの主目的に近い方を選び、もう一方は `generic.yaml` の質問や Context-Specific Risk Lenses で補う

## Extension

新しいドメインを追加する場合:

1. `scripts/analyze_context.py` の `DOMAIN_PATTERNS` にパターンを追加
2. 対応する質問ファイル `references/questions/{domain}.yaml` を作成
3. `SKILL.md` の Question Selection 一覧と Inference Hints に追記
