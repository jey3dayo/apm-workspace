# gh-address-comments の来歴

- 上流 repo / パス / コミット: `openai/plugins` / `plugins/github/skills/gh-address-comments` / `11c74d6`
- 退役コミット: `33bd952`
- Salvage: 2026-08-28 に catalog へ移動（commit `ef965c3`）
- 移動: 2026-09-02 に `manual-skills` へ移動
- 改変点: コネクタ参照を `gh` CLI に置換。2026-10-05 に `scripts/fetch_comments.py` へ argv での PR 指定（`[<owner>/<repo>] <number|URL>`、解決失敗は usage + exit 2）を追加。SKILL.md の「PR を渡されたらそれを使う」とスクリプトが食い違っていたため。2026-11-09 に引数なし（カレントブランチ）経路も PR URL から base repo を解決するよう統一し、fork PR で head repo 側を引く問題を修正（openai/skills#495 と同根）。
- 再確認条件: 上流または後継が復活したら、外部依存へ戻す。
