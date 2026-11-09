# APM native の配布（mise 入口、first cut）

- Status: 2026-11-09、APM 0.35.0。`apply` は使い捨ての HOME だけに配る。実 HOME とその祖先、その中の tool の状態（`.apm`・`.claude`・`.codex`・`.cursor`・`.agents`・`.config`・`.cache`・`.local`・`Library`）を、何も書く前に拒否する。`apply --real-home` は、下の「実 HOME への切り替えの blocker」のため拒否する。MCP・認証・permissions・settings は書き換えない（install は `--only apm`）
- 今の位置づけ: 新しい HOME と使い捨ての HOME に配るための経路。今の実 HOME（旧経路が配った状態）への切り替えは、下の「実 HOME への切り替えの blocker」が解けるまで行わない
- テスト: `tests/native-distribution.bats`（`mise run test:sh` に含まれる）。この checkout の `catalog/` と `manual-skills/` を fixture の git repo に入れ、実 APM で使い捨ての HOME へ配る。macOS では `sandbox-exec` が通信と fixture の外への書込みを拒否する。fixture の置き場所は `APM_NATIVE_FIXTURE_ROOT` で変えられる

## 入口

| mise task                                                                          | すること                                                                                                                                                                                                                                                                                              |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mise run native:plan`                                                             | 既定の入口。consumer の manifest と、apply が実行する手順を表示する。何も書かない                                                                                                                                                                                                                     |
| `mise run native:render -- --source-ref <SHA>`                                     | consumer の manifest を標準出力に出す                                                                                                                                                                                                                                                                 |
| `mise run native:apply -- --home <使い捨ての HOME> --source-ref <SHA>`             | manifest を `<HOME>/.apm/apm.yml` に書き、`HOME=<HOME>` で `apm install -g --only apm` と `apm compile -g --clean` を実行する                                                                                                                                                                         |
| `mise run native:backup -- --real-home --backup-dir <新しいディレクトリ>`          | rehearse の材料として、apply が変え得る非秘密のパス（下の「backup の対象」）と agmsg の store を clone copy する。既存の backup は上書きしない                                                                                                                                                        |
| `mise run native:rehearse -- --real-home --backup-dir <backup> --source-ref <SHA>` | backup を `<backup>/rehearsal-<UTC>/home` に複製し、HOME の外を指すリンクを複製の中へ向け直してから、同じ install と compile を実行する。消えたファイルを `lost.txt` に数え、結果を `result.txt` に書く。install・compile が成功して消えたファイルが 0 件のときだけ成功で終わる。実 HOME には書かない |
| `mise run native:apply -- --real-home ...`                                         | 拒否する（「実 HOME への切り替えの blocker」）。何も書かない                                                                                                                                                                                                                                          |

- consumer の manifest は、root の `apm.yml` の `jey3dayo/apm-workspace/catalog#main` と `manual-skills#main` の 2 行を、指定した commit SHA への pin に書き換えたもの。外部の依存と MCP はそのまま通す（外部の依存はもともと SHA で pin している）。`--workspace-only` を付けると、この repo の 2 package だけを残す
- 配布と更新を分ける: apply は pin を自分で動かさない。新しい commit を配るときは、`--source-ref` に新しい SHA を渡して実行し直す。外部の依存の pin は、今と同じく root の `apm.yml` で上げる
- 生成した root（`~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`）が APM の目印を残したまま compile のあとに編集されていたら、何も書かずに止まる。APM の目印は編集を守らず、compile が上書きするため。判定は APM と同じ Build ID の照合（`apm_cli/compilation/build_id.py`）で、APM と同じく末尾の改行だけを足した・消した編集は検出しない
- `<HOME>/.apm/apm.yml` が描画した manifest とバイト単位で違えば、`apm.yml.<UTC>.bak` に残してから置き換える（同じ名前があれば番号を付け、既存の `.bak` を上書きしない）
- HOME の外を指す（または壊れた）symlink か、ハードリンクの通常のファイルが HOME の中にあれば、何も書かずに止まる。apm がリンクを通して HOME の外のファイルを書き換えるため（キャッシュの `Library/Caches/apm` のように、配布先より深い場所にも書く）。rehearse は、複製の中のリンクをすべて複製の中へ向け直し、同じ検査を通してから install する
- `<HOME>/.apm/config.json` に `default_client` と `prefer_ssh` 以外のキーがあれば、apply も rehearse も止まる。APM は `temp_dir` などの書込み先をここから読むため。`prefer_ssh` は git の URL の形を変えるだけで、書込み先は変えない。キーは APM と同じく JSON としてデコードしてから比べる
- apm は空の環境に `HOME`・`PATH`・ロケール・git の設定の場所と、HOME の中の `TMPDIR`（`.cache/apm-native-tmp`）だけを渡して起動する。APM は `APM_CACHE_DIR` や `XDG_*`、`TMPDIR` が指す場所にも書き（`APM_CACHE_DIR` と `XDG_CACHE_HOME` はテストで確かめた）、git は token・proxy・askpass を環境から読むため
- manifest は同じディレクトリの新しいファイルに書いてから名前を置き換える
- install は `--only apm`。MCP は、旧経路と `setup:mcp:host` が書いた今の設定のまま触らない

backup の対象（rehearse が複製に再現するもの）: `~/.apm/apm.yml`・`config.json`・`apm.lock.yaml`・`deployment-receipts`（APM が配った成果物の所有の記録）、`~/.claude/{skills,agents,rules,commands,CLAUDE.md}`、`~/.codex/{AGENTS.md,rules}`、`~/.cursor/{agents,rules,AGENTS.md}`、`~/.agents/skills`、`~/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.local/state/agmsg`（別に取る）

## 旧経路と新経路

|                                         | 旧経路（`mise run deploy` → `scripts/apm-workspace.sh apply`）                                           | 新経路（`mise run native:apply`）                                                                                   |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| consumer の manifest                    | この checkout の `apm.yml`（`catalog#main` は浮動の ref）                                                | `<HOME>/.apm/apm.yml` に描画したもの（この repo を SHA で pin）                                                     |
| skills                                  | 自作の writer が stage して入れ替える（`build_target_skill_trees` → `replace_skill_targets_from_stage`） | `apm install -g`                                                                                                    |
| agents                                  | APM で一時的な project に render し、自前で置く（`deploy_catalog_agents_via_apm`）                       | `apm install -g`。Codex には `catalog/apm.yml` の `targets` で配らない                                              |
| 共通ガイド                              | `apm compile -g --clean`（`compile_user_root_contexts`）と、OpenCode・Pi へのコピー                      | `apm compile -g --clean`。Claude には `~/.claude/rules/ai-collaboration.md` として届く                              |
| `catalog/rules`・`catalog/claude/rules` | 自前の同期（`sync_managed_catalog_runtime_assets`）                                                      | 手動（下の表）                                                                                                      |
| 他の tool が置く skill（Herdr など）    | `config/preserved-skills-root-entries.txt` で除外する                                                    | APM は自分の持ち物ではないものに触らない（テストで確かめた）                                                        |
| agmsg の `db`・`teams`                  | apply の中で save/restore する                                                                           | rehearse が複製の中で同じ `scripts/agmsg-state.sh` で save/restore する。実 HOME への apply は blocker で止めている |

## native と手動の境界

分類の意味:

- **native**: APM が配る
- **手動（レイアウト）**: APM の primitive として置いていないので配られない。`.apm/` の下へ移せば native になり得るが、配られる tool が変わるので、この PR では動かさない
- **手動（APM 非対応）**: APM 0.35.0 の仕組みでは扱えない
- **first cut の外**: 今回は扱わない

| 対象                                                     | 分類               | 手動の手順・理由                                                                                                                                                                                                                                   | 確認状況                                                                                      |
| -------------------------------------------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `catalog/.apm/skills`・`manual-skills/.apm/skills`       | native             | -                                                                                                                                                                                                                                                  | 観測（使い捨ての HOME で、Claude と `~/.agents/skills` の `SKILL.md` が元と byte 単位で一致） |
| `catalog/.apm/agents`                                    | native             | Codex には配らない（`docs/package-decisions.md` の Codex 変換の却下）                                                                                                                                                                              | 観測（Claude と Cursor に届き、`~/.codex/agents` は作られない）                               |
| `catalog/.apm/instructions`                              | native             | compile が Codex と Cursor の root を書く。Claude には rule として届く。手書きの `~/.claude/CLAUDE.md` は残る                                                                                                                                      | 観測                                                                                          |
| root `apm.yml` の外部の依存                              | native             | -                                                                                                                                                                                                                                                  | 描画だけ確かめた（テストは通信しないので install は未確認）                                   |
| root `apm.yml` の `mcp:`                                 | first cut の外     | manifest には残すが、install は `--only apm` なので配らない。MCP は今の設定のまま                                                                                                                                                                  | -                                                                                             |
| `catalog/rules/claude-md-design.md`                      | 手動（レイアウト） | `~/.claude/rules/` へコピーする。旧経路は Codex・Cursor・OpenCode の `rules/` にも置いていたが、それぞれの tool がそこの `.md` を読むかは確かめていない                                                                                            | 未確認                                                                                        |
| `catalog/claude/rules/model-policy.md`                   | 手動（レイアウト） | `~/.claude/rules/` へコピーする。Claude だけに向けた rule で、instructions にすると Codex・Cursor の root にも入る。1 つの instruction を Claude だけに配れるかは確かめていない                                                                    | 未確認                                                                                        |
| agmsg の `db`・`teams`（`~/.agents/skills/agmsg/` の中） | 手動（APM 非対応） | APM は skill のディレクトリを置き換えるので、リンクが消える。rehearse は複製の中で既存の `scripts/agmsg-state.sh` で save/restore する。実 HOME で同じことをする経路は、blocker が解けたときに戻す。skill の中の `run/` が消えるかは確かめていない | テスト（apm の stub でディレクトリを置き換えて確かめた）                                      |
| private skills（`private-skills/.apm/skills`）           | first cut の外     | consumer の `~/.apm/skills/` に置けば local content として配られる（PR79 で観測）。同名の catalog skill を上書きできるかは確かめていない                                                                                                           | 未確認                                                                                        |
| OpenCode（`~/.config/opencode/AGENTS.md`）               | 手動（APM 非対応） | APM の opencode target は制限付きの agent を受け付けないので、targets に入れない。ガイドは手で置く                                                                                                                                                 | ソース（`sync_opencode_instructions` のコメント）                                             |
| Pi（`~/AGENTS.md`）                                      | first cut の外     | ガイドを手で置く。APM に Pi の target があるかは確かめていない                                                                                                                                                                                     | 未確認                                                                                        |
| host-local の MCP                                        | 手動（APM 非対応） | 今と同じく `mise run setup:mcp:host`（`mise bootstrap`）                                                                                                                                                                                           | ソース                                                                                        |
| Cursor の `~/.cursor/mcp.json`                           | 手動（APM 非対応） | 今と同じく手で管理する                                                                                                                                                                                                                             | ソース                                                                                        |
| この repo の `.apm/skills`、`optional-skills/`           | first cut の外     | 配布ではない（作業用の bridge と、使う repo が入れる skill）                                                                                                                                                                                       | -                                                                                             |

手動の項目のために、新しい同期の処理は足さない。

## 既知の問題

- consumer の状態と authoring の checkout が同じ `~/.apm` にある。APM 0.35.0 は user scope を `~/.apm` に固定しているので、実 HOME への apply は、checkout が追跡している `~/.apm/apm.yml`（と APM が書く `apm.lock.yaml`）を書き換える。main の checkout は dirty になり、`git pull` は止まり、旧経路の `mise run deploy` も描画した manifest を読む。分けるには checkout を `~/.apm` の外へ移す必要があり、それは別の判断にする
- 目印の無い root（旧経路がコピーした `~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`）は、`compile -g --clean` が上書きしない。Claude には旧い `CLAUDE.md` と native の rule `ai-collaboration.md` の両方が届く。`mise run migrate:roots`（既定は dry-run）で旧いコピーを退避するのは別の手順

- 既存の `smoke:catalog`（pre-push hook と `verify`）が、実 HOME の `~/.apm/deployment-receipts` に一時ディレクトリの receipt を書く。backup の前後を比べるときは、native の副作用と取り違えない

## 実 HOME への切り替えの blocker

2026-11-09 に実 HOME へ一度 apply し、実害が出たので rollback した（backup した 15 パスは差分 0 に戻った）。

- `apm install -g --only apm` が、旧経路の配った skill のファイルを消し（stale-file cleanup）、同じファイルの書込みは「no trustworthy local deployment baseline」で飛ばした。最後は Codex native plugin を持つ package（`nanaism/yomiyasu`）の移行で止まった（`apm_cli/install/phases/codex_plugins.py`）。`.agents/skills` に旧経路が置いたファイルが残っていると、APM は移行を拒否する
- backup を複製した使い捨ての HOME で再現した。元の `catalog#main` の manifest でも SHA pin の manifest でも同じように失敗したので、pin の書き方は原因ではない
- `apm install --dry-run` は、消すファイルを表示しない（APM 自身が「Orphan removals are not previewed」と出す）。事前の確認には `native:rehearse` を使う
- Codex native plugin の移行は Codex の RPC で plugin を登録する。成功しても Codex 側の状態を書き換えるので、「設定を書き換えない」という条件とぶつかる
- APM（upstream）の挙動なので、この repo の修正では制御できない。解くには、旧経路の配った skill の置き場をまるごと退避してから配り直すか（private skill は入れ直す）、Codex を targets から外すか、を決める必要がある。どちらもまだ決めていない

切り替えの途中で `~/.cache/apm` を退避したときの戻し方: 作り直された `~/.cache/apm` を新しい名前（`apm.native-regen-<UTC>` など）へ移し、退避したもの（`apm.native-aside-<UTC>`）を `~/.cache/apm` に戻す。どちらも消さない。2026-11-09 の実 HOME の apply が `.cache/apm` の中の上流の symlink（同じ checkout の中で切れた相対リンクや、上流の絶対パスのリンク）で止まるのは、この退避ではなくキャッシュの扱いを直すべき問題として残している

## 退役の境界

新経路は旧経路と併存させる。3 つ目の常設の配布経路にはしない。新経路で配ることが定着したら、`native:*` を `deploy` の中身に置き換え、次を退役させる。

- 退役させるもの: 自作の skills writer（`build_target_skill_trees`・`replace_skill_targets_from_stage` とその stage・衝突検査）、agents の自前の配置（`deploy_catalog_agents_via_apm`）、`sync_managed_catalog_runtime_assets`、catalog の stage・bundle・register（`prepare:catalog`・`install:catalog`）、`config/preserved-skills-root-entries.txt`、それらを確かめるテスト
- 残すもの: `scripts/agmsg-state.sh`、`setup:mcp:host`、SHA pin の検証（`validate:workspace`）、`scripts/native.sh`
- 旧経路のテストは、退役させるときに一緒に外し、外す理由（その経路がもう無い）を記録する

## blocker が解けたあとの手順（今は実行しない）

1. `mise run native:plan -- --source-ref <merge 済みの SHA>` で manifest を確かめる。package の pin は merge 済みの commit にする
2. `mise run native:backup -- --real-home --backup-dir <新しいディレクトリ>`
3. `mise run native:rehearse -- --real-home --backup-dir <同じディレクトリ> --source-ref <同じ SHA>`。成功で終わり、`lost.txt` が空であることを確かめる
4. 実 HOME への apply と、その戻し方（backup を戻す手順、agmsg のリンクの save/restore、backup のあとの変化の検出）は、blocker を解く方針（旧経路の置き場の退避か、Codex を targets から外すか）を決めてから作り直す。2026-11-09 の版は PR #80 の履歴（559bd87）にある

## 確かめていないこと

- 本番の HOME での出力が旧経路と同じになるか（skill 数、Herdr など他の tool の skill、private の上書きの組み合わせ）
- 外部の依存の install（テストは通信しない）
- 各 tool が実際に rule とガイドを読み込むか
- Linux（`sandbox-exec` が無い）では、通信と書込みを強制的には止めない。テストが守るのは HOME のガードと `env -i` の隔離まで
- Windows（対象外）
