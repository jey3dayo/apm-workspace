# Skill Overlaps

役割の近いスキルの使い分けと、どれを残すか検証中の組み合わせをまとめています。
各スキルがどのレーンにあるかは [`skill-inventory.md`](skill-inventory.md)、採用・撤去の判断は [`package-decisions.md`](package-decisions.md) に記録しています。

## デザイン / UI・UX / レビュー系の役割マップ

経緯は [`package-decisions.md`](package-decisions.md) の「デザイン / UI・UX / レビュー系スキルの棲み分け」を参照してください。

| 役割                                                     | スキル                                                                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 0→1 デザイン選定（スタイル・色・フォント）               | `ui-ux-pro-max`（本体のみ）                                                                                            |
| アクセシビリティ修正                                     | `fixing-accessibility`（ibelick）                                                                                      |
| モーション taste・レビュー・監査                         | `emil-design-eng` / `review-animations` / `improve-animations` / `find-animation-opportunities`（emilkowalski/skills） |
| モーション実装スニペット                                 | `transitions-dev`                                                                                                      |
| UI レビューのレーン選択（lane 1 がデザインシステム準拠） | `review-board`（optional、自作）                                                                                       |
| デザインドキュメント                                     | `design-md-workflow`（catalog 自作）                                                                                   |
| コードベース監査→計画（汎用）                            | `improve`（shadcn）                                                                                                    |
| React 診断                                               | `react-doctor`（millionco）                                                                                            |
| React の hook 選択・Effect の要否・React 19 非同期 hook  | `react-hooks-refactoring`（catalog 自作。性能規則は `react-best-practices` に委ねます）                                |

## レビュー系の使い分け

- UI のアクセシビリティ → `fixing-accessibility`
- デザインシステム・トークン準拠 → `review-board`（lane 1、optional）
- アニメーション・モーションの質 → `review-animations`（単発）/ `improve-animations`（全体監査→plan 生成）
- UI・フォーム・アクセシビリティ・マルチデバイスのレーン振り分け → `review-board`（optional）
- コード品質全般 → 組み込み `/code-review` / `thermo-nuclear-code-quality-review`
- diff を人間が TUI で見てコメントをやり取りする → `tuicr`
- 改善候補の洗い出し（実装はしない）→ `improve`（shadcn、汎用）

## 検証中の競合スキル

同じ依頼で複数のスキルが候補になる組み合わせです。どれを残すかは実際に使って判断します。
判定の期限と完了条件は組み合わせごとに `todo.txt` に置き、結論が出たら結果を `package-decisions.md` に記録してこの表から行を外します。
自動起動はまれで `/skill` の明示起動が中心のため、「発火 0」は撤去の理由にしません。
自動で選ばれるかどうかは `~/.claude/settings.json` の `skillOverrides` と各 `SKILL.md` の `disable-model-invocation` で決まります。

| 組み合わせ     | スキル                                                         | 重なる依頼       | 現状                                                                                                                                                             | 撤去を判断する基準                             |
| -------------- | -------------------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| コードレビュー | `thermo-nuclear-code-quality-review` / 組み込み `/code-review` | 「レビューして」 | thermo-nuclear は自動起動しません。公式 docs の `/code-review` は正確性バグが対象で、構造や保守性の監査とは軸が異なります。2026-10-08 に共存で様子見と決めました | 指摘が `/code-review` と重なりすぎたら外します |
