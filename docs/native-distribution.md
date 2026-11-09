# APM native の配布（mise 入口、first cut）

- Status: 2026-11-09、APM 0.35.0。使い捨ての HOME にだけ適用できる。本番の切り替え（cutover）は承認されておらず、`scripts/native.sh` は実 HOME とその祖先、その中の tool の状態（`.apm`・`.claude`・`.codex`・`.cursor`・`.agents`・`.config`・`.cache`・`.local`・`Library`）を、何も書く前に拒否する
- テスト: `tests/native-distribution.bats`（`mise run test:sh` に含まれる）。この checkout の `catalog/` と `manual-skills/` を fixture の git repo に入れ、実 APM で使い捨ての HOME へ配る。macOS では `sandbox-exec` が通信と fixture の外への書込みを拒否する。fixture の置き場所は `APM_NATIVE_FIXTURE_ROOT` で変えられる

## 入口

| mise task                                                              | すること                                                                                                           |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `mise run native:plan`                                                 | 既定の入口。consumer の manifest と、apply が実行する手順を表示する。何も書かない                                  |
| `mise run native:render -- --source-ref <SHA>`                         | consumer の manifest を標準出力に出す                                                                              |
| `mise run native:apply -- --home <使い捨ての HOME> --source-ref <SHA>` | manifest を `<HOME>/.apm/apm.yml` に書き、`HOME=<HOME>` で `apm install -g` と `apm compile -g --clean` を実行する |

- consumer の manifest は、root の `apm.yml` の `jey3dayo/apm-workspace/catalog#main` と `manual-skills#main` の 2 行を、指定した commit SHA への pin に書き換えたもの。外部の依存と MCP はそのまま通す（外部の依存はもともと SHA で pin している）。`--workspace-only` を付けると、この repo の 2 package だけを残す
- 配布と更新を分ける: apply は pin を自分で動かさない。新しい commit を配るときは、`--source-ref` に新しい SHA を渡して実行し直す。外部の依存の pin は、今と同じく root の `apm.yml` で上げる
- 生成した root（`~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`）が APM の目印を残したまま compile のあとに編集されていたら、何も書かずに止まる。APM の目印は編集を守らず、compile が上書きするため
- `<HOME>/.apm/apm.yml` が描画した manifest と違えば、`apm.yml.<UTC>.bak` に残してから置き換える

## 旧経路と新経路

|                                         | 旧経路（`mise run deploy` → `scripts/apm-workspace.sh apply`）                                           | 新経路（`mise run native:apply`）                                                      |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| consumer の manifest                    | この checkout の `apm.yml`（`catalog#main` は浮動の ref）                                                | `<HOME>/.apm/apm.yml` に描画したもの（この repo を SHA で pin）                        |
| skills                                  | 自作の writer が stage して入れ替える（`build_target_skill_trees` → `replace_skill_targets_from_stage`） | `apm install -g`                                                                       |
| agents                                  | APM で一時的な project に render し、自前で置く（`deploy_catalog_agents_via_apm`）                       | `apm install -g`。Codex には `catalog/apm.yml` の `targets` で配らない                 |
| 共通ガイド                              | `apm compile -g --clean`（`compile_user_root_contexts`）と、OpenCode・Pi へのコピー                      | `apm compile -g --clean`。Claude には `~/.claude/rules/ai-collaboration.md` として届く |
| `catalog/rules`・`catalog/claude/rules` | 自前の同期（`sync_managed_catalog_runtime_assets`）                                                      | 手動（下の表）                                                                         |
| 他の tool が置く skill（Herdr など）    | `config/preserved-skills-root-entries.txt` で除外する                                                    | APM は自分の持ち物ではないものに触らない（テストで確かめた）                           |
| agmsg の `db`・`teams`                  | apply の中で save/restore する                                                                           | 手動（下の表）                                                                         |

## native と手動の境界

分類の意味:

- **native**: APM が配る
- **手動（レイアウト）**: APM の primitive として置いていないので配られない。`.apm/` の下へ移せば native になり得るが、配られる tool が変わるので、この PR では動かさない
- **手動（APM 非対応）**: APM 0.35.0 の仕組みでは扱えない
- **first cut の外**: 今回は扱わない

| 対象                                                     | 分類               | 手動の手順・理由                                                                                                                                                                | 確認状況                                                                                      |
| -------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `catalog/.apm/skills`・`manual-skills/.apm/skills`       | native             | -                                                                                                                                                                               | 観測（使い捨ての HOME で、Claude と `~/.agents/skills` の `SKILL.md` が元と byte 単位で一致） |
| `catalog/.apm/agents`                                    | native             | Codex には配らない（`docs/package-decisions.md` の Codex 変換の却下）                                                                                                           | 観測（Claude と Cursor に届き、`~/.codex/agents` は作られない）                               |
| `catalog/.apm/instructions`                              | native             | compile が Codex と Cursor の root を書く。Claude には rule として届く。手書きの `~/.claude/CLAUDE.md` は残る                                                                   | 観測                                                                                          |
| root `apm.yml` の外部の依存                              | native             | -                                                                                                                                                                               | 描画だけ確かめた（テストは通信しないので install は未確認）                                   |
| root `apm.yml` の `mcp:`                                 | native             | -                                                                                                                                                                               | 描画だけ確かめた（install は未確認）                                                          |
| `catalog/rules/claude-md-design.md`                      | 手動（レイアウト） | `~/.claude/rules/` へコピーする。旧経路は Codex・Cursor・OpenCode の `rules/` にも置いていたが、それぞれの tool がそこの `.md` を読むかは確かめていない                         | 未確認                                                                                        |
| `catalog/claude/rules/model-policy.md`                   | 手動（レイアウト） | `~/.claude/rules/` へコピーする。Claude だけに向けた rule で、instructions にすると Codex・Cursor の root にも入る。1 つの instruction を Claude だけに配れるかは確かめていない | 未確認                                                                                        |
| agmsg の `db`・`teams`（`~/.agents/skills/agmsg/` の中） | 手動（APM 非対応） | APM は skill のディレクトリを置き換えるので、リンクが消える。install の前に `mise run agmsg:state:save`、後に `mise run agmsg:state:restore` を実行する                         | ソース（AGENTS.md の「agmsg State」）                                                         |
| private skills（`private-skills/.apm/skills`）           | first cut の外     | consumer の `~/.apm/skills/` に置けば local content として配られる（PR79 で観測）。同名の catalog skill を上書きできるかは確かめていない                                        | 未確認                                                                                        |
| OpenCode（`~/.config/opencode/AGENTS.md`）               | 手動（APM 非対応） | APM の opencode target は制限付きの agent を受け付けないので、targets に入れない。ガイドは手で置く                                                                              | ソース（`sync_opencode_instructions` のコメント）                                             |
| Pi（`~/AGENTS.md`）                                      | first cut の外     | ガイドを手で置く。APM に Pi の target があるかは確かめていない                                                                                                                  | 未確認                                                                                        |
| host-local の MCP                                        | 手動（APM 非対応） | 今と同じく `mise run setup:mcp:host`（`mise bootstrap`）                                                                                                                        | ソース                                                                                        |
| Cursor の `~/.cursor/mcp.json`                           | 手動（APM 非対応） | 今と同じく手で管理する                                                                                                                                                          | ソース                                                                                        |
| この repo の `.apm/skills`、`optional-skills/`           | first cut の外     | 配布ではない（作業用の bridge と、使う repo が入れる skill）                                                                                                                    | -                                                                                             |

手動の項目のために、新しい同期の処理は足さない。

## 退役の境界（切り替えが承認されたあと）

新経路は、切り替えが承認されるまで旧経路と併存させる。3 つ目の常設の配布経路にはしない。切り替えのあと、`native:*` を `deploy` の中身に置き換え、次を退役させる。

- 退役させるもの: 自作の skills writer（`build_target_skill_trees`・`replace_skill_targets_from_stage` とその stage・衝突検査）、agents の自前の配置（`deploy_catalog_agents_via_apm`）、`sync_managed_catalog_runtime_assets`、catalog の stage・bundle・register（`prepare:catalog`・`install:catalog`）、`config/preserved-skills-root-entries.txt`、それらを確かめるテスト
- 残すもの: `scripts/agmsg-state.sh`、`setup:mcp:host`、SHA pin の検証（`validate:workspace`）、`scripts/native.sh`
- 旧経路のテストは、退役させるときに一緒に外し、外す理由（その経路がもう無い）を記録する。この PR では旧経路もそのテストも変えていない

## 切り替えと戻し方（preview。この PR では実行していない）

切り替え（承認されたあと）:

1. `mise run native:plan -- --source-ref <origin/main の SHA>` で manifest を確かめる
2. 今の `~/.apm/apm.yml`・`apm.lock.yaml` と、`~/.claude`・`~/.codex`・`~/.cursor`・`~/.agents/skills` を退避する
3. `mise run agmsg:state:save`
4. `native.sh` の実 HOME の拒否を、明示した切り替えのフラグがあるときだけ外す（この変更自体を別の PR にする）
5. `native:apply` を実 HOME に対して実行する
6. `mise run agmsg:state:restore` を実行し、上の表の手動の項目を置く
7. `mise run doctor` と、各 tool での読込を確かめる

戻し方:

1. 退避した `~/.apm/apm.yml`・`apm.lock.yaml` を戻す
2. 退避した配布先を戻すか、旧経路の `mise run deploy` を実行する
3. `mise run agmsg:state:restore`

## 確かめていないこと

- 本番の HOME での出力が旧経路と同じになるか（skill 数、Herdr など他の tool の skill、private の上書きの組み合わせ）
- 外部の依存と MCP の install（テストは通信しない）
- 各 tool が実際に rule とガイドを読み込むか
- Linux（`sandbox-exec` が無い）では、通信と書込みを強制的には止めない。テストが守るのは HOME のガードと `env -i` の隔離まで
- Windows（対象外）
