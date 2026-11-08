# Asana → Linear 変換メモ

## フィールド対応

- Asana `name` → Linear `title`
- Asana `notes` → Linear `description`
- Asana `due_on` / `due_at` → Linear `dueDate` (YYYY-MM-DD)
- Asana `assignee` → Linear `assigneeId`（必要なら別途ユーザー解決）
- Asana `projects` / `sections` → Linear `team` / `state`
- Asana `custom_fields` → description に構造化追記（例: 箇条書き）

## 運用ルール

- 期限が本文にある場合も、Linear の dueDate に必ず設定する。
- 支払い/金額などの計算対象は本文に行単位で追記する（集計しやすい形式）。
- 1件ずつ API 連打せず、可能な限りまとめて作成・更新する。

## 推奨本文フォーマット（支払いメモ）

取引ログの書式は SKILL.md の「コメント・本文の書式」に従う（日付 | 支払い手段 | 金額）。Asana 側の店名・状態は issue 本文に書く。

## 状態名の例

チームごとに異なるため、まず `states` で取得してからマッピングする。

- Asana `New` → Linear `Triage` / `Todo`
- Asana `In Progress` → Linear `In Progress`
- Asana `Done` → Linear `Done`
