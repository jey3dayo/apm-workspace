# 推奨ワークフロー（経路の選択）

- 役割分担: `orchestrator-worker` は委譲判定・タスク分割・**Reviewer と Worker の model 選定**の正本、`agmsg-delegation` は transport の正本
- 先に `orchestrator-worker` で model を決め、その model と必要な強制境界を満たせる transport を選ぶ。 組み込みサブエージェント（Agent tool / `spawn_agent`）で満たせるならそれを使い、満たせないなら `agmsg-delegation` を使う。「組み込みが使えるなら常に組み込み」ではない——review 外注の既定は差分を書いた runtime の逆側なので、Claude が書いた差分の review は `agmsg-delegation` で Codex へ出す
- 実行時に read-only を強制できていない経路の reviewer を verdict へ格上げしない（判定は `agmsg-delegation`）
- Worker のモデル名をユーザーが指定したら（例:「luna で」）、それが platform を跨ぐ明示指示にあたる。既定は同一 platform 内で完結させる
- pane / workspace を勝手に作らない。ユーザーが「用意して」と指示したときだけ作り、作った実体を読み戻してから報告する。手順は `herdr` スキルと `agmsg-delegation` の `references/resident-pool.md` が正本（具体コマンドをここに写さない）
- エージェント / セッション間の引き継ぎ（CC → Codex 等）は transport に `agmsg` を使い、本文は `agmsg-delegation` の引き継ぎメッセージ書式（artifact は参照渡し・suggested skills・secrets redact・次セッションの目的に合わせる）に従う
- agmsg が全断（`team.sh` が `Team not found`、`identities.sh` が空）したら `~/.apm` で `mise run doctor` を読み、plain path が無いと確認できたときだけ `mise run agmsg:state:restore` を実行する（plain 側の roster を上書きで失うため）。手順は `agmsg-delegation` の `references/roster-recovery.md`
- Worker の `DONE` は未検証の申告として扱う。Orchestrator が実際の比較元を確定し、差分、変更対象、要求との対応を独立に確認する
- DoD に定める full gate は Orchestrator が実行し、Worker の実行報告では代替しない
- タスクで明示されていない依存 version、manifest、lockfile の変更は、要求上の必要性を確認できない限り採用しない
