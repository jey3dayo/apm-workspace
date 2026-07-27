# Linear ラベル一覧（team: JEY / 取得日: 2026-07-27）

## ラベル

- Research
- term
  - term:daily
  - term:weekly
  - term:monthly
  - term:quarterly
  - term:semiannual
  - term:yearly
- risk
  - risk:unknown
  - risk:P0
  - risk:P1
  - risk:P2
  - risk:P3
- household
  - household:utilities（光熱費・通信・生活インフラ）
  - household:shopping（買い物・価格比較）
  - household:car（車・交通関連）
  - household:insurance（保険・保障）
  - household:tax（税金・控除・ふるさと納税）
  - household:finance（家計・資金計画）
  - household:childcare（育児・子ども関連）
  - household:house（住宅・土地・建築）
- LT
- Bug
- Improvement
- Feature

## 使い分けの実例

- 期限・周期管理: `term:*`（例: `term:monthly`, `term:yearly`）
- 緊急度・重要度: `risk:*`（例: `risk:P1`, `risk:P3`）
- household プロジェクトの領域分類: `household:*`
- 研究・検証: `Research`
- 種別: `Bug` / `Improvement` / `Feature`

## 注意

- ラベルはチームごとに異なる。
- 最新化は Linear MCP の `list_issue_labels`（`team: JEY`）で取得し、このファイルを更新する。
