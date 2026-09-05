# 初回利用前の smoke

runtime（Claude / Codex）ごとに、実際に次の5点を確認してから常用する。

境界（1・2）は LLM worker を回さず `codex sandbox` で直接叩く。worker に「書けなかったか」を報告させると、モデルの自己申告に依存するうえ、失敗の原因が境界なのか指示の解釈なのか切り分けられない。

1. review は対象 project への write が拒否される。`codex sandbox -P :workspace -p agmsg-review -C <scratch> /usr/bin/touch <project>/probe` が `Operation not permitted` で失敗し、同じコマンドで `<scratch>/probe` は成功する
2. implement は対象 project 内の write が成功し project 外の write が拒否される。cwd を対象 project にして同様に確認する
3. `send-report.sh` による READY send 成功
4. DONE / REVIEW send 成功
5. 全手順が承認画面・MCP 確認画面なしで完了する

## scratch と probe 先の置き場所

- `/tmp` と `$TMPDIR` は Codex の workspace-write が既定で書込可にする（base config に `exclude_slash_tmp` / `exclude_tmpdir_env_var` が無い）。**拒否を確認する先には使えない**。書けることを確認する scratch 側には使ってよい
- 登録済み repo の内側（`tmp/` 配下を含む）を対象にすると `join.sh` / `reset.sh` が外側 repo へ正規化する。`AGMSG_RESOLVE_PROJECT=0` を付ける（SKILL.md Lifecycle 3 参照）
- 組み込み permission profile `:workspace` は `sandbox_workspace_write` の `writable_roots` を捨てて exclude flag だけ読む。`writable_roots` の効き目はこの smoke では見られないため、`assert_writable_roots_are_canonical` と bats の静的検査で担保する
