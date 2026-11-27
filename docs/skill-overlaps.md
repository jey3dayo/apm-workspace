# Skill Overlaps

役割の近いスキルの使い分けと、どれを残すか検証中の組み合わせをまとめています。
各スキルがどのレーンにあるかは [`skill-inventory.md`](skill-inventory.md) に、採用・撤去の判断は [`package-decisions.md`](package-decisions.md) に記録しています。

## デザイン / UI・UX / レビュー系の役割マップ

経緯は [`package-decisions.md`](package-decisions.md) の「デザイン / UI・UX / レビュー系スキルの棲み分け」を参照してください。

| 役割                                                     | スキル                                                                                                                                                            |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0→1 デザイン選定（スタイル・色・フォント）               | `ui-ux-pro-max`（本体のみ）                                                                                                                                       |
| AI っぽい UI の改善・再設計                              | `unslop-ui`（heydamir/unslop）                                                                                                                                    |
| アクセシビリティ修正                                     | `fixing-accessibility`（ibelick）                                                                                                                                 |
| UI ポリッシュ・モーション設計・レビュー・監査・性能調査  | `emil-design-eng` / `apple-design` / `review-animations` / `improve-animations` / `find-animation-opportunities` / `animation-performance`（emilkowalski/skills） |
| 最悪データによる UI ストレス検証                         | `break-ui`（emilkowalski/skills）                                                                                                                                 |
| モーション実装スニペット                                 | `transitions-dev`                                                                                                                                                 |
| UI レビューのレーン選択（lane 1 がデザインシステム準拠） | `review-board`（optional、自作）                                                                                                                                  |
| デザインドキュメント                                     | `design-md-workflow`（catalog 自作）                                                                                                                              |
| コードベース監査→計画（汎用）                            | `improve`（shadcn）                                                                                                                                               |
| React 診断                                               | `react-doctor`（millionco）                                                                                                                                       |
| React の hook 選択・Effect の要否・React 19 非同期 hook  | `react-hooks-refactoring`（catalog 自作。性能規則は `react-best-practices` が担当）                                                                               |

## レビュー系の使い分け

- UI のアクセシビリティ → `fixing-accessibility`
- デザインシステム・トークン準拠 → `review-board`（lane 1、optional）
- UI の境界値・最悪ケース検証 → `break-ui`
- アニメーション・モーションの質と性能 → `review-animations`（単発）/ `improve-animations`（全体監査→plan 生成）/ `animation-performance`（フレーム落ち原因調査）
- UI・フォーム・アクセシビリティ・マルチデバイスのレーン振り分け → `review-board`（optional）
- PR 前の diff 仕上げ（コメント圧縮・テストの実装詳細依存の除去など） → `polish`
- コメントの要不要の確認 → `no-comments`（pstack）
- 出荷前の影響範囲の実証 → `blast-radius`（pstack）
- 反復レビューと合議レビュー → `sol-loop`（通常の反復）/ `council`（heavy な変更の複数プロバイダ合議）
- コード品質全般 → 組み込み `/code-review` / `thermo-nuclear-code-quality-review`
- diff を人間が TUI で見てコメントをやり取りする → `tuicr`
- 改善候補の洗い出し（実装はしない） → `improve`（shadcn、汎用）

## 日本語執筆・推敲系の使い分け

経緯は [`package-decisions.md`](package-decisions.md) の「2026-11-06 日本語の推敲を `yomiyasu` に寄せた」を参照してください。

- 他者が読む長い日本語文書の通常の推敲 → `explain-before-shorten`（口頭で伝わる構成にして短く整える）のあとに `yomiyasu`（表現の仕上げ）
- 構成や冗長さを含めて推敲・清書するとき → `natural-japanese`（構成と冗長さの見直し）→ 技術文書では必要に応じて `japanese-tech-writing`（段落構成・論証の厳密さ）→ `yomiyasu`（表現の仕上げ）

## 検証中の競合スキル

同じ依頼で複数のスキルが候補になる組み合わせです。どれを残すかは実際に使って判断します。
期限や完了条件を決めた組み合わせは `todo.txt` で管理し、結論が出たら結果を `package-decisions.md` に記録してこの表から行を外します。
自動起動はまれで `/skill` の明示起動が中心のため、「発火 0」は撤去の理由にしません。
自動で選ばれるかどうかは `~/.claude/settings.json` の `skillOverrides` と各 `SKILL.md` の `disable-model-invocation` で決まります。

| 組み合わせ     | スキル                                                         | 重なる依頼       | 現状                                                                                                                                                                                   | 撤去を判断する基準                             |
| -------------- | -------------------------------------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| コードレビュー | `thermo-nuclear-code-quality-review` / 組み込み `/code-review` | 「レビューして」 | `thermo-nuclear-code-quality-review` は自動起動しません。公式 docs の `/code-review` は正確性バグが対象で、構造や保守性の監査とは軸が異なります。2026-10-08 に共存で様子見と決めました | 指摘が `/code-review` と重なりすぎたら外します |
