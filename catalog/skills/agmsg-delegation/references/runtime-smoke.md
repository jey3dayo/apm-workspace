# 初回利用前の smoke

runtime（Claude / Codex）ごとに、実際に次の5点を確認してから常用する。

境界（1・2）は LLM worker を回さず `codex sandbox` で直接叩く。worker に「書けなかったか」を報告させると、モデルの自己申告に依存するうえ、失敗の原因が境界なのか指示の解釈なのか切り分けられない。

1. review は対象 project への write が拒否される。`codex sandbox -P :workspace -p agmsg-review -C <scratch> /usr/bin/touch <project>/probe` が `Operation not permitted` で失敗し、同じコマンドで `<scratch>/probe` は成功する
2. implement は対象 project 内の write が成功し project 外の write が拒否される。cwd を対象 project にして同様に確認する
3. `send-report.sh` による READY send 成功
4. DONE / REVIEW send 成功
5. 全手順が承認画面・MCP 確認画面なしで完了する

## cursor の smoke

境界は `run-cursor-worker.sh` が生成した profile を `sandbox-exec -f <profile>` で直接叩き、LLM worker を回さない（理由は上と同じ）。拒否確認先に `/tmp` と `$TMPDIR` を使わない注意（下の「scratch と probe 先の置き場所」）はそのまま適用される——`run-cursor-worker.sh` の write allowlist にも `/tmp` / `$TMPDIR` / `runtime_dir` が含まれるため、これらの下では書込が成功してしまい拒否の確認にならない。

1. review profile 下で対象 project への write が拒否され、ファイルが実体として存在しない。`sandbox-exec -f <review-profile> /usr/bin/touch <project>/probe` が `Operation not permitted` で失敗し、`test -e <project>/probe` が偽であることを確認する
2. implement で project 内の write が成功し、project 外（review-profile 生成時に deny した対象や `~/.cursor` の外側任意パス）の write は拒否される
3. `send-report.sh` による READY send 成功
4. DONE / REVIEW send 成功
5. 全手順が承認画面なしで完走する

MCP / tool 面の不在は上記1〜5とは別の capability check として確認する。`sandbox-exec -f <profile> cursor-agent mcp list` の出力が次のどちらかであることを確認する——これは `~/.cursor` 全面 read 拒否の副作用が効いていることの確認であり、write 境界が成立している証拠にはならない（両者を混同しない）。

- `No MCP servers configured`（cwd が `~/.cursor/projects/<slug>/` を持たない場合）
- `Failed to list MCP servers: EPERM ... <read deny した根の下のパス>`（cwd が cursor project entry を持つ場合。実測では `~/.cursor/projects/<slug>/mcp-approvals.json`）

**出力が cwd で変わるため、前者だけを合格条件にしない。** 通常の作業リポジトリは cursor project entry を持つので、前者だけを条件にすると helper が常に起動を拒否する（2026-09-18 に実測）。EPERM を受理するときは、拒否されたパスが自分で read deny した根の下にあることまで確かめる。素の状態（sandbox なし）では 7 件が `: ready` として並ぶので、遮断が効いていないことは別の形で明確に分かる。

## scratch と probe 先の置き場所

- `/tmp` と `$TMPDIR` は Codex の workspace-write が既定で書込可にする（base config に `exclude_slash_tmp` / `exclude_tmpdir_env_var` が無い）。**拒否を確認する先には使えない**。書けることを確認する scratch 側には使ってよい
- 登録済み repo の内側（`tmp/` 配下を含む）を対象にすると `join.sh` / `reset.sh` が外側 repo へ正規化する。`AGMSG_RESOLVE_PROJECT=0` を付ける（SKILL.md Lifecycle 3 参照）
- 組み込み permission profile `:workspace` は `sandbox_workspace_write` の `writable_roots` を捨てて exclude flag だけ読む。`writable_roots` の効き目はこの smoke では見られないため、`assert_writable_roots_are_canonical` と bats の静的検査で担保する
