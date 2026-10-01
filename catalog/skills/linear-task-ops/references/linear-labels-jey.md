# Linear ラベル一覧（team: JEY / 取得日: 2026-10-01）

## ラベル

- term
  - term:daily
  - term:weekly
  - term:monthly
  - term:quarterly
  - term:semiannual
  - term:yearly
- Bug
- Feature
- Improvement

## 使い分けの実例

- 期限・周期管理: `term:*`（例: `term:monthly`, `term:yearly`）
- 種別（開発系プロジェクト）: `Bug` / `Feature` / `Improvement`
- 領域はプロジェクト、緊急度・重要度は Priority で表す

## retire 済み（新しい issue には付けない）

- `risk:*`（Priority へ移行）、`household:*` と `domain`（project で足りる）、`Research`（labs で足りる）、`LT`

## 注意

- ラベルはワークスペース共通。
- 最新化は Linear MCP の `list_issue_labels`（`team: JEY`）で取得し、このファイルを更新する。retire 済みは `retiredAt` で判別する。
