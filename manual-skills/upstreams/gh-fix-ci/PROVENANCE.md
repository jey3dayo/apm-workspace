# gh-fix-ci の来歴

- 上流 repo / パス / コミット: `openai/plugins` / `plugins/github/skills/gh-fix-ci` / `11c74d6`
- 退役コミット: `33bd952`
- Salvage: 2026-08-28 に catalog へ移動（commit `ef965c3`）
- 移動: 2026-09-02 に `manual-skills` へ移動
- 改変点: コネクタ参照を `gh` CLI に置換。以後は改変しない方針。
- 保守例外（2026-10-11、ユーザー明示承認）: Check URL に `jobId` がある場合は `gh run view --job ... --log` で対象 job のログを選び、取得できないときも run 全体のログをその job の原因として代用しない。この修正のみ「以後は改変しない」方針の例外とする。上流 repo / path / commit の参照は変更しない。
- 再確認条件: 上流または後継が復活したら、外部依存へ戻す。
