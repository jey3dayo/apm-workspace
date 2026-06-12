# Similarity Report Analysis

`similarity-ts` レポートの読み方と、共通化計画の立て方。

## レポートの構造

実際の出力（v0.5.0）は関数と型でフォーマットが異なる。

```
=== Function Similarity ===
Found 7 duplicate pairs:
------------------------------------------------------------

Similarity: 93.57%, Score: 4.7 points (lines 5~5, avg: 5.0)
  src/admin-service.ts:4-8 getAdminById
  src/user-service.ts:4-8 getUserById

=== Type Similarity ===
Similar types found:
------------------------------------------------------------

Similarity: 98.12% (structural: 100.00%, naming: 95.29%)
  src/types.ts:1 | L1-5 similar-type: UserCreateInput (interface)
  src/types.ts:13 | L13-17 similar-type: MemberCreateInput (interface)
```

- Similarity: 類似度スコア。関数側はサイズペナルティ適用後の値（短い関数は割引かれる）
- Score (points): 類似度 × 平均行数ベースの優先度指標。大きいほどリファクタ価値が高い
- 各行: `ファイル:行範囲 シンボル名`。型は `(interface)` / `(type)` の種別付き

## 解析手順

1. ペアを類似度順に分類する（95%+ / 90-95% / 87-90%）
2. 各ペアの実コードを読み、差分の種類を判定する
   - 表記揺れ（変数名・対象モデルだけが違う）→ 共通化候補
   - ビジネスロジック差（バリデーション・権限・副作用が違う、または今後分岐する見込み）→ 保留
3. 同じ抽出テーマに収束するペアはテーマ単位に集約する（派生ペアを個別候補として数えない）
4. 共通化するテーマだけを計画に載せ、保留理由も含めて生レポートとは別ファイル（`tmp/similarity-plan.md` など）にまとめる

## 計画テンプレート

レビュー用途（コードを変更しない依頼）でもこのテンプレートを流用し、「手順」チェックリストは「共通化する場合の推奨手順」という条件付き提案に読み替える。

```markdown
## 解析サマリー

- 検出: N ペア（実行コマンド: similarity-ts -t 0.9 src/）
- 共通化対象: X ペア / 保留: Y ペア（理由付き）

## リファクタリング計画

### <共通化テーマ名>

- 対象ペア: <関数名 vs 関数名>（類似度 %）
- 抽出先: <新しい共通関数・型の置き場所>
- 影響範囲: <参照ファイル数・テストの有無>
- 手順:
  - [ ] 既存動作を保証するテストの確認・作成
  - [ ] 共通実装の作成
  - [ ] 呼び出し側を 1 箇所ずつ移行
  - [ ] type-check / lint / test
```

## 共通化時のチェック

- 参照箇所を先に確認する（Serena `find_referencing_symbols`、使えなければ `rg` で全参照を列挙）
- テストが無い箇所は共通化前に書く
- 共通関数のシグネチャに `any` を使わない。ジェネリクスか専用インターフェースで受ける
- 型定義の統合は「共通基底型 + 拡張」を基本とし、無理な合成はしない

## 効果測定

リファクタ後に同条件で再実行し、ペア数の変化を記録する。

```bash
similarity-ts -t 0.9 src/ > tmp/similarity-after.md
# Before: 15 pairs -> After: 3 pairs
```
