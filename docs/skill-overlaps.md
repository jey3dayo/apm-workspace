# Skill Overlaps

役割の近いスキルのうち、どれを使うかの使い分けと、どれを残すか検証中の組み合わせ。
各スキルがどのレーンにあるかは [`skill-inventory.md`](skill-inventory.md)、採用・撤去の判断は [`package-decisions.md`](package-decisions.md) に置く。

## デザイン / UI・UX / レビュー系の役割マップ

経緯は [`package-decisions.md`](package-decisions.md) の「デザイン / UI・UX / レビュー系スキルの棲み分け」。

| 役割                                                     | スキル                                                                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 0→1 デザイン選定（スタイル・色・フォント）               | `ui-ux-pro-max`（本体のみ）                                                                                            |
| 美的方向性・脱テンプレ                                   | `frontend-design`（anthropics）                                                                                        |
| ベースライン修正（deslop）                               | `baseline-ui` / `fixing-accessibility` / `fixing-metadata`（ibelick）                                                  |
| モーション taste・レビュー・監査                         | `emil-design-eng` / `review-animations` / `improve-animations` / `find-animation-opportunities`（emilkowalski/skills） |
| モーション実装スニペット                                 | `transitions-dev`                                                                                                      |
| UI レビューのレーン選択（lane 1 がデザインシステム準拠） | `review-board`（optional、自作）                                                                                       |
| 既存 UI の監査 → 実装 plan（read-only）                  | `improve-ui`（ibelick）                                                                                                |
| デザインドキュメント                                     | `design-md-workflow`（catalog 自作）                                                                                   |
| コードベース監査→計画（汎用）                            | `improve`（shadcn）                                                                                                    |
| React 診断                                               | `react-doctor`（millionco）                                                                                            |

## レビュー系の使い分け

- UI の見た目・ガイドライン準拠 → `baseline-ui`（deslop）
- デザインシステム・トークン準拠 → `review-board`（lane 1、optional）
- アニメーション・モーションの質 → `review-animations`（単発）/ `improve-animations`（全体監査→plan 生成）
- UI・フォーム・アクセシビリティ・マルチデバイスのレーン振り分け → `review-board`（optional）
- コード品質全般 → 組み込み `/code-review` / `hunk-review` / `thermo-nuclear-code-quality-review`
- 改善候補の洗い出し（実装しない）→ `improve`（shadcn、汎用）/ `improve-ui`（UI に限る）

## 検証中の競合スキル

同じ依頼で複数のスキルが候補になる組み合わせ。どれを残すかは使ってみて決める。
判定の期限と完了条件は `todo.txt` に組み合わせごとに置き、判定したら結果を `package-decisions.md` に書いて行を外す。
自動起動はまれで `/skill` の明示起動が中心なので、「発火 0」は撤去の理由にしない。
自動で選ばれるかどうかは `~/.claude/settings.json` の `skillOverrides` と各 `SKILL.md` の `disable-model-invocation` で決まる。

| 組み合わせ             | スキル                                                                                                    | 重なる依頼                                      | 現状                                                                                                                                                          | 撤去を判断する基準                                                                                                                                                                     |
| ---------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 日本語の推敲           | `natural-japanese` / `yomiyasu`                                                                           | 「AI臭さを消して」「自然な日本語にして」        | 両方とも自動起動する。`japanese-tech-writing` は技術書の規範で別扱い                                                                                          | 同じ依頼で両方が動いて出力が混ざるなら、推敲で劣るほうを `user-invocable-only` にするか外す                                                                                            |
| UI の改善              | `ui-ux-pro-max` / `baseline-ui` / `frontend-design` / `improve-ui`                                        | 「この UI を良くして」「見た目を整えて」        | 上の役割マップで分けている                                                                                                                                    | 役割マップのとおりに選べないなら、マップを直すか片方を抑える                                                                                                                           |
| アニメーション         | `review-animations` / `improve-animations` / `find-animation-opportunities` / `fixing-motion-performance` | 「アニメーションを見て」「滑らかに動かして」    | `review-animations` は自動起動しない。基準の `emil-design-eng` と、手動起動の実績がある `apple-design` / `transitions-dev` は維持と決めて判定の対象から外した | `emil-design-eng` で代わりが利くもの（`review-animations`、`fixing-motion-performance`）から外す。`improve-animations` と `find-animation-opportunities` は `improve` で足りるなら外す |
| コードレビュー         | `thermo-nuclear-code-quality-review` / 組み込み `/code-review`                                            | 「レビューして」                                | thermo-nuclear は自動起動しない                                                                                                                               | 指摘が `/code-review` と重なりすぎたら外す                                                                                                                                             |
| PR 前の掃除            | `polish` / 組み込み `/simplify`                                                                           | 「PR 前に diff を整えて」                       | `polish` は `ship` の最初の工程でも呼ばれる                                                                                                                   | `/simplify` が `polish` の観点（コメント圧縮、テストの実装詳細依存、型逃げ）を拾わないなら両方残し、`polish` の description に境界を書く                                               |
| 対話的な diff レビュー | `hunk-review` / `tuicr`                                                                                   | 「diff のレビューセッションにコメントを足して」 | どちらもツール本体（Hunk / tuicr）が前提                                                                                                                      | 常用しているツールのほうだけ残す                                                                                                                                                       |
| 図解                   | `show-me` / `archify`                                                                                     | 「仕組みを図にして」                            | `archify` は `name-only`                                                                                                                                      | 使った実績のあるほうを残す                                                                                                                                                             |
