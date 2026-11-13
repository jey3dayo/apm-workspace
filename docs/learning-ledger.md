# Learning Ledger

`learning-intake` が `applied` にした変更を、効いたかどうかで採点するための台帳。memory ではない。学びそのものの正本は各 owner ファイルにある。

- 追記: `learning-intake` §4 で `applied` にした行ごとに1行足す。判定は `未計測` で始める
- 採点: 次の `learning-intake` の §1 で、判定が `効いた` / `対応済み` 以外の行のうち確認方法の信号が見えるものを `効いた` / `一部` / `効かなかった` / `未検証` で採点し、判定根拠に件数・出力・発言を書く
- `効かなかった`: その変更を owner から外すか、lint などより強い形に作り直す案を `learning-intake` の §2 以降に通す。済んだら判定を `対応済み` に書き換え、結果を判定根拠に追記する（作り直した変更は新しい行になる）

列の意味:

- 日付: `applied` にした日（`YYYY-MM-DD`）
- 学び: 一行の要約
- owner: 変更したファイル1つ
- 確認方法: §3 で決めた「何を見れば変わったと言えるか」
- 判定 / 判定根拠: 採点の結果と、その裏付け

記録の中の `~/.apm` は、2026-11-10 の切り替えまで authoring checkout だった場所を指す（今は `~/src/github.com/jey3dayo/apm-workspace`）。

<!-- prettier-ignore -->
| 日付       | 学び                                                                    | owner                                                              | 確認方法                                                                                                   | 判定   | 判定根拠 |
| ---------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ------ | -------- |
| 2026-11-06 | CI の `mise run` 例が `install: false` でも全ツールを入れる矛盾を直した | `catalog/skills/ci-stability-hooks/references/actions-lockfile.md` | 例が `--skip-tools` 経由で、次に actions.lock の CI を作る報告に同じ回避策（`mise exec` への置換）が出ない | 未計測 |          |
| 2026-11-06 | 外した voicevox を指す音声通知ルールを削除した                          | `catalog/AGENTS.md`                                                | `grep -rn 'mcp-simple-voicevox\|音声通知' catalog` が 0 件で、音声通知の未実施を指摘する報告が出ない       | 未計測 |          |
| 2026-11-06 | 受入れの提示を「学び・owner・次回の振る舞い」の 3 列にし、根拠と確認方法は求められたときだけ出す | `catalog/skills/learning-intake/SKILL.md` | 次の受入れで、提示が 3 列の表と y/n だけになり、「情報が多い」の訂正が出ない | 未計測 | |
| 2026-11-06 | 台帳の表を `prettier-ignore` で整形の対象から外し、行を足したときの差分を 1 行にした | `docs/learning-ledger.md` | 次に行を足したとき、差分が追記の 1 行だけになり、`atomic-commit` が行単位で分けられる | 未計測 | |
| 2026-11-06 | セッションログの数え方（`server_tool_use` など）を `references/` に足し、報告にセッション ID を書かせる | `catalog/skills/learning-intake/SKILL.md` | 次のログ集計で `server_tool_use` の見落とし・`-` 始まりのパス誤読が起きず、報告からセッションを 1 件で特定できる | 一部 | 今回の2報告のIDから同一Codexセッションの分割ログ2本を特定した。Claudeのtool集計は未検証 |
| 2026-11-06 | 反映の報告の末尾に、次にやること（コミット・保留の再開条件・滞留）を添える完了条件を足した | `catalog/skills/learning-intake/SKILL.md` | 次の受入れの報告の末尾に、次にやることが 1〜2 行ある | 未計測 | |
| 2026-11-06 | `~/.apm` で引数なしに呼ばれ、未処理があるときは受入れ経路を既定にした | `catalog/skills/learning-intake/SKILL.md` | 引数なしの `/learning-intake` で、経路の確認を挟まず受入れが始まる | 未計測 | |
| 2026-11-06 | `git-branch-cleanup` の worktree 除外条件に、パスを使う生きたプロセス（`lsof +D`）を足した | `catalog/skills/git-branch-cleanup/SKILL.md` | 次に dev stack が動く worktree を掃除するとき、候補から除外されるか確認を求められ、削除後に tilt などが壊れない | 未計測 | |
| 2026-11-06 | Worker の検証に、実 cwd（`git rev-parse --show-toplevel`）の報告と、主 checkout の前後比較を求めるようにした | `catalog/skills/orchestrator-worker/SKILL.md` | 次の worktree Worker の報告に cwd 出力が付き、書込み先の取り違えが主 checkout の差分で検出される | 未計測 | |
| 2026-11-06 | 検証コマンドは repo の `mise` task と CI 定義から確認して写し、独自フラグは理由を書くようにした | `catalog/skills/orchestrator-worker/SKILL.md` | 次の Worker の検証コマンドが repo の gate と一致し、独自フラグの失敗が gate との差として報告される | 未計測 | |
| 2026-11-06 | `apm-deploy-verify` に、archify の既知の link 警告（アンカー付きと例文中のリンク）を既知として扱う旨を足した | `catalog/skills/apm-deploy-verify/SKILL.md` | 次の deploy 検証の報告で、archify の警告を「原因未調査」と申し送らず、既知の 1 行で済ませる | 未計測 | |
| 2026-11-06 | `ship` の push 工程に、`push.followTags` で意図しない tag が送られないよう `--dry-run` で確かめ、`--no-follow-tags` を使う手順を足した | `catalog/skills/ship/SKILL.md` | 次に fork や初回の branch へ push するとき、送る ref を事前に確認し、branch 以外の tag が fork に増えない | 未計測 | |
| 2026-11-13 | `run-codex-worker.sh` の既定 effort コメントから、出典のない「Terra high 相当を最安で達成」の比較を外した | `catalog/.apm/skills/agmsg-delegation/scripts/run-codex-worker.sh` | 次に Worker の既定 model や effort を議論するとき、このコメントを根拠として引かれず、luna xhigh と terra の比較は実測の todo として扱われる | 未計測 | |
