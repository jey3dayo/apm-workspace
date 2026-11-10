# APM native の配布（mise 入口、first cut）

- Status: 2026-11-09、APM 0.35.0。`apply` は使い捨ての HOME だけに配る。実 HOME とその祖先、その中の tool の状態（`.apm`・`.claude`・`.codex`・`.cursor`・`.agents`・`.config`・`.cache`・`.local`・`Library`）を、何も書く前に拒否する。`apply --real-home` は拒否する。実 HOME に書く入口は `migrate` と、その取り消しの `migrate-rollback`・`reinstate`（どれも `.bak-<UTC>` の記録を持つ root だけを動かし、何も消さない）で、`migrate` は `rehearse --migrate` が clean に終わった backup の複製があるときに限る（下の「実 HOME への切り替えの解き方」）。MCP・認証・permissions・settings は書き換えない（install は `--only apm`）
- 今の位置づけ: 実 HOME は 2026-11-10 に native へ切り替え済みで、authoring の checkout は `~/.apm` の外（`~/src/github.com/jey3dayo/apm-workspace`）にある。この経路は、新しい HOME と使い捨ての HOME に配るためと、旧経路が配った状態の HOME を退避して切り替える `migrate` のためにある
- テスト: `tests/native-distribution.bats`（`mise run test:sh` に含まれる）。この checkout の `catalog/` と `manual-skills/` を fixture の git repo に入れ、実 APM で使い捨ての HOME へ配る。macOS では `sandbox-exec` が通信と fixture の外への書込みを拒否する。fixture の置き場所は `APM_NATIVE_FIXTURE_ROOT` で変えられる

## 入口

| mise task                                                                                                                     | すること                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mise run native:plan`                                                                                                        | 既定の入口。consumer の manifest と、apply が実行する手順を表示する。何も書かない                                                                                                                                                                                                                                                                                                                                                                                          |
| `mise run native:render -- --source-ref <SHA>`                                                                                | consumer の manifest を標準出力に出す                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `mise run native:apply -- --home <使い捨ての HOME> --source-ref <SHA>`                                                        | manifest を `<HOME>/.apm/apm.yml` に書き、`HOME=<HOME>` で `apm install -g --only apm --trust-bin` と `apm compile -g --clean` を実行する                                                                                                                                                                                                                                                                                                                                  |
| `mise run native:backup -- --real-home --backup-dir <新しいディレクトリ>`                                                     | rehearse の材料として、apply が変え得る非秘密のパス（下の「backup の対象」）と agmsg の store を clone copy する。既存の backup は上書きしない                                                                                                                                                                                                                                                                                                                             |
| `mise run native:rehearse -- --real-home --backup-dir <backup> --source-ref <SHA>`                                            | backup を `<backup>/rehearsal-<UTC>/home` に複製し、HOME の外を指すリンクを複製の中へ向け直してから、同じ install と compile を実行する。消えたファイルを `lost.txt` に数え、結果を `result.txt` に書く。install・compile が成功して消えたファイルが 0 件のときだけ成功で終わる。実 HOME には書かない                                                                                                                                                                      |
| `mise run native:rehearse -- --real-home --backup-dir <backup> --source-ref <SHA> --migrate`                                  | 複製の中で、install の前に 4 つの root を `<root>.bak-<UTC>` へ移し、compile のあとに入れ直す（`migrate` と同じ関数）。消えてよいのは「rehearse --migrate が見ること」の表（`allowed_lost_reason`）にある path だけで、その件数は `result.txt` の `allowed_lost=` に出る。それ以外が消える、入れ直しが失敗する、`apm.log` に `no trustworthy local deployment baseline` が出る、のどれかなら失敗。`result.txt` は `mode=migrate` になる（`--migrate` なしは `mode=plain`） |
| `mise run native:migrate -- (--real-home \| --home <HOME>) --source-ref <SHA> --rehearsal <rehearsal-UTC> [--workspace-only]` | 実 HOME を切り替える。順序は下の「migrate の順序」。失敗したら自動で rollback して非 0 で終わる。成功すると UTC の stamp と rollback のコマンドを表示する                                                                                                                                                                                                                                                                                                                  |
| `mise run native:migrate-rollback -- (--real-home \| --home <HOME>) --stamp <UTC>`                                            | 今の 4 つの root を `<root>.native-<UTC>` へ移し、`<root>.bak-<UTC>` を元の場所へ戻す。どちらも消さない。agmsg のリンクも戻す                                                                                                                                                                                                                                                                                                                                              |
| `mise run native:reinstate -- (--real-home \| --home <HOME>) --stamp <UTC>`                                                   | `<root>.bak-<UTC>` の top-level の entry のうち、今の root に無いものだけを戻す（`migrate` の入れ直しを単独で呼ぶ）                                                                                                                                                                                                                                                                                                                                                        |
| `mise run native:apply -- --real-home ...`                                                                                    | 拒否する。実 HOME に書くのは `migrate` と、その取り消しの `migrate-rollback`・`reinstate` だけ。何も書かない                                                                                                                                                                                                                                                                                                                                                               |

- consumer の manifest は、root の `apm.yml` の `jey3dayo/apm-workspace/catalog#main` と `manual-skills#main` の 2 行を、指定した commit SHA への pin に書き換えたもの。`nanaism/yomiyasu/skills/yomiyasu#<SHA>` の 1 行は、構造化した形（`git: nanaism/yomiyasu` / `ref: <SHA>` / `skills: [yomiyasu]`）に書き換える。SHA は root の行から読み、対応表（`scripts/native.sh` の `EXTERNAL_PACKAGE_MAP`）の行が root に無ければ render は失敗する。そのほかの外部の依存と MCP はそのまま通す（外部の依存はもともと SHA で pin している）。root の `apm.yml` と `apm.lock.yaml` は変えない。`--workspace-only` を付けると、この repo の 2 package だけを残す（外部の依存ごと落ちるので、yomiyasu の変換も要らない）
- 配布と更新を分ける: apply は pin を自分で動かさない。新しい commit を配るときは、`--source-ref` に新しい SHA を渡して実行し直す。外部の依存の pin は、今と同じく root の `apm.yml` で上げる
- 生成した root（`~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`）が APM の目印を残したまま compile のあとに編集されていたら、何も書かずに止まる。APM の目印は編集を守らず、compile が上書きするため。判定は APM と同じ Build ID の照合（`apm_cli/compilation/build_id.py`）で、APM と同じく末尾の改行だけを足した・消した編集は検出しない
- `<HOME>/.apm/apm.yml` が描画した manifest とバイト単位で違えば、`apm.yml.<UTC>.bak` に残してから置き換える（同じ名前があれば番号を付け、既存の `.bak` を上書きしない）
- HOME の外を指す（または壊れた）symlink か、ハードリンクの通常のファイルが HOME の中にあれば、何も書かずに止まる。apm がリンクを通して HOME の外のファイルを書き換えるため（キャッシュの `Library/Caches/apm` のように、配布先より深い場所にも書く）。rehearse は、実 HOME の 4 つの root（`.agents/skills`・`.claude/skills`・`.claude/agents`・`.cursor/agents`）に壊れたリンクか HOME の外へ出るリンクがあれば、`migrate` と同じ判定（`escaping_link_line`）で、複製を作る前にそのリンクの名前を出して失敗する。root の外のリンクは、複製の中を複製の中へ向け直し（先が無ければ外す。外したリンクの名前は出す）、同じ検査を通してから install する
- `<HOME>/.apm/config.json` に `default_client` と `prefer_ssh` 以外のキーがあれば、apply も rehearse も止まる。APM は `temp_dir` などの書込み先をここから読むため。`prefer_ssh` は git の URL の形を変えるだけで、書込み先は変えない。キーは APM と同じく JSON としてデコードしてから比べる
- `<HOME>/apm.yml` があれば、apply・rehearse（実 HOME と複製の両方）・migrate は何も書かずに止まる。user scope の APM は executable の許可を `<HOME>/apm.yml` が在ればそちらから読み、`<HOME>/.apm/apm.yml` の `allowExecutables` を無視するため（`apm_cli/security/executables.py` の `exec_trust_context_for_project`）
- apm は空の環境に `HOME`・`PATH`・ロケール・git の設定の場所と、HOME の中の `TMPDIR`（`.cache/apm-native-tmp`）だけを渡して起動する。APM は `APM_CACHE_DIR` や `XDG_*`、`TMPDIR` が指す場所にも書き（`APM_CACHE_DIR` と `XDG_CACHE_HOME` はテストで確かめた）、git は token・proxy・askpass を環境から読むため
- manifest は同じディレクトリの新しいファイルに書いてから名前を置き換える
- install は `--only apm`。MCP は、`setup:mcp:host` などが書いた今の設定のまま触らない

backup の対象（rehearse が複製に再現するもの）: `~/.apm/apm.yml`・`config.json`・`apm.lock.yaml`・`deployment-receipts`（APM が配った成果物の所有の記録）、`~/.claude/{skills,agents,rules,commands,CLAUDE.md}`、`~/.codex/{AGENTS.md,rules}`、`~/.cursor/{agents,rules,AGENTS.md}`、`~/.agents/skills`、`~/AGENTS.md`、`~/.config/opencode/AGENTS.md`、`~/.local/state/agmsg`（別に取る）

## 切り替えのあとの authoring checkout

`scripts/apm-workspace.sh` は、`APM_WORKSPACE_DIR` が無いとき、`<HOME>/.apm` に `.git`（linked worktree ではファイル）か `catalog/` があればそれを、無ければこの repo の root（`REPO_ROOT`）を `$WORKSPACE_DIR` にする。切り替えのあとは checkout の外から `validate`・`validate:catalog`・`smoke:catalog` がその checkout に対して動く。`.git` の検査は、worktree の `.git` ファイルも通す。PowerShell 版（`scripts/apm-workspace.ps1` の `$WorkspaceDir`）は今も `<HOME>/.apm` を既定にしているので、Windows で切り替えのあとに使うなら同じ既定へ揃える必要がある（Windows は対象外としているので、揃えていない）。

## native と手動の境界

分類の意味:

- **native**: APM が配る
- **手動（レイアウト）**: APM の primitive として置いていないので配られない。`.apm/` の下へ移せば native になり得るが、配られる tool が変わるので、この PR では動かさない
- **手動（APM 非対応）**: APM 0.35.0 の仕組みでは扱えない
- **first cut の外**: 今回は扱わない

| 対象                                                     | 分類               | 手動の手順・理由                                                                                                                                                                                                       | 確認状況                                                                                             |
| -------------------------------------------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `catalog/.apm/skills`・`manual-skills/.apm/skills`       | native             | -                                                                                                                                                                                                                      | 観測（使い捨ての HOME で、Claude と `~/.agents/skills` の `SKILL.md` が元と byte 単位で一致）        |
| `catalog/.apm/agents`                                    | native             | Codex には配らない（`docs/package-decisions.md` の Codex 変換の却下）                                                                                                                                                  | 観測（Claude と Cursor に届き、`~/.codex/agents` は作られない）                                      |
| `catalog/.apm/instructions`                              | native             | compile が Codex と Cursor の root を書く。Claude には rule として届く。手書きの `~/.claude/CLAUDE.md` は残る                                                                                                          | 観測                                                                                                 |
| root `apm.yml` の外部の依存                              | native             | -                                                                                                                                                                                                                      | 描画だけ確かめた（テストは通信しないので install は未確認）                                          |
| root `apm.yml` の `mcp:`                                 | first cut の外     | manifest には残すが、install は `--only apm` なので配らない。MCP は今の設定のまま                                                                                                                                      | -                                                                                                    |
| `catalog/rules/claude-md-design.md`                      | 手動（レイアウト） | `~/.claude/rules/` へコピーする。旧経路は Codex・Cursor・OpenCode の `rules/` にも置いていたが、それぞれの tool がそこの `.md` を読むかは確かめていない                                                                | 未確認                                                                                               |
| `catalog/claude/rules/model-policy.md`                   | 手動（レイアウト） | `~/.claude/rules/` へコピーする。Claude だけに向けた rule で、instructions にすると Codex・Cursor の root にも入る。1 つの instruction を Claude だけに配れるかは確かめていない                                        | 未確認                                                                                               |
| agmsg の `db`・`teams`（`~/.agents/skills/agmsg/` の中） | 手動（APM 非対応） | APM は skill のディレクトリを置き換えるので、リンクが消える。rehearse と migrate は既存の `scripts/agmsg-state.sh` で save/restore し、migrate-rollback はリンクを戻す。skill の中の `run/` が消えるかは確かめていない | テスト（apm の stub でディレクトリを置き換えて確かめた。migrate はリンクが往復で戻ることを確かめた） |
| private skills（`private-skills/.apm/skills`）           | first cut の外     | consumer の `~/.apm/skills/` に置けば local content として配られる（PR79 で観測）。同名の catalog skill を上書きできるかは確かめていない                                                                               | 未確認                                                                                               |
| OpenCode（`~/.config/opencode/AGENTS.md`）               | 手動（APM 非対応） | APM の opencode target は制限付きの agent を受け付けないので、targets に入れない。ガイドは手で置く                                                                                                                     | ソース（`sync_opencode_instructions` のコメント）                                                    |
| Pi（`~/AGENTS.md`）                                      | first cut の外     | ガイドを手で置く。APM に Pi の target があるかは確かめていない                                                                                                                                                         | 未確認                                                                                               |
| host-local の MCP                                        | 手動（APM 非対応） | 今と同じく `mise run setup:mcp:host`（`mise bootstrap`）                                                                                                                                                               | ソース                                                                                               |
| Cursor の `~/.cursor/mcp.json`                           | 手動（APM 非対応） | 今と同じく手で管理する                                                                                                                                                                                                 | ソース                                                                                               |
| この repo の `.apm/skills`、`optional-skills/`           | first cut の外     | 配布ではない（作業用の bridge と、使う repo が入れる skill）                                                                                                                                                           | -                                                                                                    |

手動の項目のために、新しい同期の処理は足さない。

## 既知の問題

- APM 0.35.0 は user scope を `~/.apm` に固定している。`~/.apm` が checkout だと、実 HOME へ配ったときに、checkout が追跡している `apm.yml`（と APM が書く `apm.lock.yaml`）を書き換えてしまう。main の checkout は dirty になり、`git pull` は止まる。この状態に戻さないために、`migrate` は `<HOME>/.apm` に `.git` か `catalog/` があるとき、またはこの repo が `<HOME>/.apm` の中にあるときに、何も書かずに止まる。`mise run check` と `verify` は実 HOME の配布先を書かず、`$WORKSPACE_DIR` の下（`.catalog-build`）と一時ディレクトリにだけ書くので、切り替えのあとも通る
- 目印の無い root（旧経路がコピーした `~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`）は、`compile -g --clean` が上書きしない。Claude には旧い `CLAUDE.md` と native の rule `ai-collaboration.md` の両方が届く。旧いコピーを退避する `migrate:roots` は 2026-11-10 に退役した。旧経路のままの HOME で必要なときは、commit `0bcce09` の旧ツールで実行するか、手で `<名前>.<UTC>.bak` へ移す
- 2026-11-10 より前の `smoke:catalog`（pre-push hook と `verify`）は、実 HOME の `~/.apm/deployment-receipts` に一時ディレクトリの receipt（root が `apm-catalog-smoke.*`）を書いていた。今は一時 HOME で apm を動かすので増えない。残っている receipt は native の副作用と取り違えない

## 実 HOME への切り替えの解き方

2026-11-09 に実 HOME へ一度 apply し、実害が出たので rollback した（backup した 15 パスは差分 0 に戻った）。原因は次の 3 つで、`migrate` はそれぞれにこう対処する。

| 起きたこと                                                                                                                                                                                                                                                                                                        | 対処                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apm install -g --only apm` が、旧経路の配った skill のファイルを消し（stale-file cleanup）、同じファイルの書込みは「no trustworthy local deployment baseline」で飛ばした。`.agents/skills` に旧経路のファイルが残っていると、Codex native plugin の移行も拒否された（`apm_cli/install/phases/codex_plugins.py`） | 4 つの root（`~/.agents/skills`・`~/.claude/skills`・`~/.claude/agents`・`~/.cursor/agents`）を、install の前に `<root>.bak-<UTC>` へ移す（削除しない）。rules と、compile が書く root（`CLAUDE.md`・`AGENTS.md`）は移さない。APM は空の root へ配る                                                                                                                                                                                                                        |
| 旧経路が配った skill のうち manifest に無いもの（private skill、Herdr などほかの tool が置いた skill、agmsg）が、移したあとの root に無い                                                                                                                                                                         | compile のあとに入れ直す（`reinstate_entries`）。固定のリストは持たず、「`.bak` にあって、install のあとの root に無い top-level の entry」を戻す。すでにあるもの（APM が配った、Herdr や Claude が書き直した）は上書きしない。`.bak` の中の symlink が root の外を指すときは、中身をコピーして戻す（配布先が authoring の checkout に依存しないため）。root の中を指すものはそのまま戻し、切れたリンクは列挙して失敗する。`mise run native:reinstate` として単独でも呼べる |
| `nanaism/yomiyasu` は Codex native plugin を持つ package で、root の `apm.yml` の書き方（`owner/repo/skills/yomiyasu#<SHA>`）だと plugin として扱われ、移行が止まった                                                                                                                                             | render が構造化した形（`git: nanaism/yomiyasu` / `ref: <SHA>` / `skills: [yomiyasu]`）に変換する。SHA は root の行から読み、行が無ければ render は失敗する                                                                                                                                                                                                                                                                                                                  |

`browser-use/browser-harness` は root の `apm.yml` で subdirectory の形（`browser-use/browser-harness/skills/browser-harness#<SHA>`）に pin していて、render はこの行をそのまま通す。repo root の形（`browser-use/browser-harness#<SHA>`）だと APM が上流の repo 全体を skill の置き場へ配り、Codex が plugin の skill として数えるため。subdirectory の形なら `SKILL.md` と `references/install.md` だけが `.agents/skills/browser-harness` と `.claude/skills/browser-harness` に入る（`skills:` の絞り込みは、この package では APM が無視するので使えない）。

APM は Codex CLI 0.163.0 だけを受け付ける（`apm_cli/codex_plugins/client.py` の `QUALIFIED_CODEX_VERSION`。上書きする手段は無い）。構造化した形が Codex native plugin の経路を通らずに skill として配られるかは、テストが通信しないので、本番の install で初めて確かめる（「確かめていないこと」）。

### bin/ の許可（`allowExecutables`）

APM 0.35.0 は、非対話の install で信頼していない package の `bin/` を配らない。旧経路が実 HOME に置いている `bin/` は `fujibee/agmsg` と `tt-a1i/archify` の 2 つだけなので、render は `--workspace-only` でないとき、manifest の末尾に次を足す（`scripts/native.sh` の `EXECUTABLE_ALLOW_PACKAGES`。この 2 つが root の `apm.yml` に無ければ render は失敗する）。

```yaml
allowExecutables:
  github.com/fujibee/agmsg:
    bin: true
  github.com/tt-a1i/archify/archify:
    bin: true
```

- 許可するのはこの 2 つの `bin/` だけ。`browser-use/browser-harness`・`mattpocock/skills`・`nextlevelbuilder/ui-ux-pro-max-skill`・`shadcn/improve` の `bin/` は、旧経路も配っていないので許可しない
- `allowExecutables` は APM では deprecated の旧名。user scope の APM は `<HOME>/apm.yml` の `executables:` を読むが、`<HOME>/.apm/apm.yml` の `executables:` は読まず、旧名の `allowExecutables:` だけを読む（`install/template.py` の `_effective_allow`、`models/apm_package.py` の `parse_allow_executables`）。そのため新しい名前では書けない。`apm approve --user` は `config.json` に書いて `assert_default_apm_config` に止められるので使わない
- 許可のキーは `github.com/<owner>/<repo>[/<path>]`。APM は依存を `str(dep_ref)`（`github.com/<repo>#<ref>`）で引き、`#<ref>` を外した形で照合する（`install/exec_gate.py` の `resolve_package_key`、`security/executables.py` の `_map_grants`）。`apm approve` が出す `fujibee/agmsg` の形は一致しない
- このブロックを書くと APM の executable のゲートが有効になり、許可していない package の hooks・MCP・LSP・canvas も default-deny になる（今は、ゲートが無いので全部配られる）。install の末尾に `executable primitives parked pending approval` という警告が出るのはこのため。`~/.apm/apm.lock.yaml` の `exec_status` に `gated_pending_approval` と残る。該当するファイルがあれば rehearse の `lost` に出る
- `apm install` には `--trust-bin` を固定で渡す（compile には渡さない）。許可があっても、stdout が端末でないと APM は `bin/` を飛ばす（`install/exec_gate.py` の `resolve_bin_skip`）。rehearse は出力を `tee` に渡すので端末でなく、migrate は端末で動くので、付けないと 2 つの結果が食い違う。許可の範囲は `allowExecutables` が決めるので、`--trust-bin` で全 package に広がらない

### rehearse --migrate が見ること

- 複製の中で、`migrate` と同じ `migrate_roots`（install の前）と `reinstate_entries`（compile のあと）を通す。end-to-end の確認は、空の HOME ではなく backup の複製から行う
- 消えてよいのは、`scripts/native.sh` の `allowed_lost_reason` に書いた allowlist だけ。件数は `allowed_lost=` に出し、`allowed-lost.txt` にタブ区切りで path と理由を残す。allowlist 以外の消失（`lost=`）が 0 件のときだけ成功する。同じ skill の別のファイルは対象外で、消えれば失敗する

  | path（HOME からの相対）                                                                                                                                              | 理由                                                                                                                                                                                                                                  |
  | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | 退避した root の中の、basename が `.apm-pin` のファイル                                                                                                              | pin の目印                                                                                                                                                                                                                            |
  | `.agents/skills/agmsg/apm.yml`、`.agents/skills/agmsg/.apm`、`.agents/skills/agmsg/.apm/.plugin-skill-sources.json`                                                  | 旧経路の stage が作るメタデータで、agmsg の scripts は参照しない                                                                                                                                                                      |
  | `.claude/skills/agmsg/` の下の、上と同じ 3 つ                                                                                                                        | 同上                                                                                                                                                                                                                                  |
  | `.agents/skills/agmsg/run` とその下                                                                                                                                  | agmsg の実行時の状態。旧経路も agmsg のディレクトリを入れ替えて作り直していて、実 HOME で `run/` の作成時刻が skill より後になっている。`.agents/skills` 側だけにある                                                                 |
  | 4 つの root の top-level の entry で、前回の native の `apm.lock.yaml`（`deployed_files`）に載っていて、今回の root に無いもの（catalog から消えた skill）の下の全部 | 前回の native では配られ、今回は配られなかったので入れ直さない（catalog から消えた skill のほか、前回と今回で配る package が違う場合も含む）。前回の lock が無い最初の `migrate` では何も該当しない。entry が今も配られていれば対象外 |

- `rehearse --migrate` は入れ直した entry を `reinstated.txt`（path と scope）、名前が同じで中身が旧い entry と違うために入れ直さなかったものを `skipped.txt` に書く（`.apm-pin` を除いて中身が同じものは載せない）。`migrate` は同じ 2 つを `<HOME>/.apm/native-migrate-<UTC>.reinstated.txt`・`.skipped.txt` に書き、`skipped.txt` が空でなければ warning を出す。単独の `reinstate` は `native-reinstate-<UTC>.` の名前で書く。private skill が catalog の skill と同じ名前で上書きしていた場合は、旧い版を手で戻す
- 前回の native の lock が載せていて、今回は配られなかった entry は、`dropped.txt` に書き、件数を `result.txt` の `dropped=` に出す。意図した削除（catalog から外した skill）だけであることを、B3 で `dropped.txt` を読んで確かめる。前回の `<HOME>/.apm/apm.yml` が `--workspace-only` で描画されたかどうかは manifest の `# native-render:` 行に残り、今回と違えば `rehearse --migrate` も `migrate` も止まる。`migrate` は同じ一覧を `<HOME>/.apm/native-migrate-<UTC>.dropped.txt` に書き、`dropped.txt` と違えば失敗して rollback する
- `apm.log` に `no trustworthy local deployment baseline` が出たら失敗する（件数は `baseline_skips=`）
- `result.txt` には `mode=migrate`、`home`、`source_ref`、`workspace_only`、各 step の status、`lost`、`allowed_lost`、`dropped`、`baseline_skips`、`previous_lock=present|absent`（`<HOME>/.apm/apm.lock.yaml` があるか）、`home_apm=checkout|consumer|absent`（`<HOME>/.apm` が checkout か、consumer か、無いか）が入る。2 つの値は backup が取った時点の HOME から `home-state.txt` に記録したもので、`rehearse` は今の HOME と違えば（checkout を移したあとなど）、記録が無い旧形式の backup と同じく、clone を作らずに失敗する。`migrate` はこれを読み、`previous_lock` と `home_apm` が今の HOME と違えば何も書かずに止まる。checkout を移す前に取った rehearsal は、移したあとには使えない（`home_apm` が `checkout` のまま）。移したあと（と、`migrate` が失敗して consumer の `~/.apm` が残ったあと）は、backup から rehearse を取り直す

### migrate の順序

1. `<HOME>/.apm` が checkout（`.git` か `catalog/`）なら止まる。この repo が `<HOME>/.apm` の中でも止まる
2. `--rehearsal` の `result.txt` を確かめる: `mode=migrate`、同じ HOME・`--source-ref`・`--workspace-only`、install・compile・入れ直し・agmsg の status が 0、`lost=0`、`baseline_skips=0`、今の HOME と同じ `previous_lock`・`home_apm`。1 つでも違えば何も書かずに止まる
3. apply と同じ guard（`config.json`、`<HOME>/apm.yml` が無いこと、compile のあとに編集された root）と、agmsg の `db`・`teams` のリンクが `<HOME>/.local/state/agmsg/` を指していること（`agmsg-state.sh` は既定の保存先にしか張り直さないので、別の保存先なら何も書かずに止まる。`rehearse --migrate` も同じ）と、HOME の外へ出るリンクと hard link の検査。`--home` は HOME 全体を、`--real-home` は APM の書込み先（退避する 4 つの root、rules、compile が書く root、`.apm`、`.cache/apm`、`Library/Caches/apm`）だけを調べる。tool のディレクトリ（`.claude` など）はリンクのときだけ調べる
4. `~/.codex/config.toml` と `~/.claude/settings.json` を、パーミッションを保ったまま `<HOME>/.apm/native-migrate-<UTC>.untouched/`（owner だけが読める）へコピーし、4 つの root の snapshot を取り、agmsg のリンクがあれば save する。中身はログに出さない
5. manifest を書く（差があれば前の manifest を `apm.yml.<UTC>.bak` に残す）。4 つの root を `<root>.bak-<UTC>` へ移し、退避した一覧を `<HOME>/.apm/native-migrate-<UTC>.txt` に記録する。`apm install -g --only apm --trust-bin`、`apm compile -g --clean`、入れ直し（入れ直しの前に、4 つの root・その `.bak-<UTC>`・`.agents`・`.claude`・`.cursor` が HOME の外を指すリンクや切れたリンクでないことを確かめる。単独の `native:reinstate` も同じ）、agmsg の restore
6. migrate が落とした entry（前回の native の lock が載せていて、今回は配られなかったもの）の一覧を `<HOME>/.apm/native-migrate-<UTC>.dropped.txt` に書き、rehearse の `dropped.txt` と違えば失敗する。続けて、rehearse と同じ消失の検査を、migrate 自身が 4 つの root の before/after の snapshot と同じ allowlist で行う。表に無いものが消えていれば失敗する（rehearse のあとに足したファイルを、APM が配り直す skill の中で失わないため）。検査の範囲は 4 つの root だけで、rehearse が見る `.claude/rules`・`.codex/rules`・compile が書く root などは、`migrate` 自身は見ない（rehearse の時点の結果に頼る）。一覧は `<HOME>/.apm/native-migrate-<UTC>.lost.txt` に残る。続けて、手順 4 の 2 つのファイルが変わっていないか比べる
7. 5 と 6 のどこかで失敗したら、自動で rollback して非 0 で終わる。2 つのファイルが変わっていたときは、手順 4 のコピーで元に戻し、migrate が残した版を `<ファイル>.changed-<UTC>` として残す。成功すると `.untouched/` を消し、UTC の stamp と rollback のコマンドを表示する

rollback（自動も `native:migrate-rollback` も）が戻すのは 4 つの root だけで、今の root は `<root>.native-<UTC>` に残る。`<HOME>/.apm/apm.yml`・`apm.lock.yaml`・`deployment-receipts`、rules、compile が書いた root は、native が書いたまま残る。これらを元に戻すには、B2 の backup（`native:backup`）と `apm.yml.<UTC>.bak` を使う。どちらも名前が既にあれば何も動かさずに失敗する。root の移動は record に `moved` を書いてから行い、移し終えたら `done` を足す。rollback は戻した root に `restored` を足すので、途中で止まった rollback は、原因を直して同じコマンドをもう一度実行すれば続きから終わる（`restored` の root は飛ばす。root を戻し終えて `restored` を書く前に止まったときは、`done` があり、`<root>.bak-<UTC>` が無く、root と `<root>.native-<UTC>` が在る組を、戻し済みとして `restored` を足す）。`done` が無く backup も無い root は、移す前に止まったものとして触らない。`done` があるのに `<root>.bak-<UTC>` が無い（手で消した）ときは、何も動かさずに止まる。

rollback で旧経路の状態へ戻した HOME は、この branch に無い旧ツール（`deploy`・`apply` など）を使って保守する。旧ツールは commit `0bcce09` にある。

`migrate` の間は Claude Code と Codex のセッションを閉じる。`~/.codex/config.toml` と `~/.claude/settings.json` が変わると失敗して元の内容を書き戻すので、その間のセッションの書込みが `<ファイル>.changed-<UTC>` に回る。この 2 つが symlink なら、復元はリンクを保ったままリンク先へ元の内容を書き戻す。リンク先が HOME の外（dotfiles の repo など）でも書き戻す（今の実 HOME では通常のファイル）。

`migrate` が失敗して自動で rollback したあとも、`<HOME>/.apm/apm.yml` は描画された manifest のままで、`~/.apm` は consumer の状態のまま残る。切り替え前（`~/.apm` が checkout）の状態へ戻すには、下の「実 HOME の checkout の移設」の「戻す」のとおり、consumer の `~/.apm` を別名へ移し、`~/.apm.checkout-<UTC>` を戻す。migrate のログにも同じ手順が出る。

### 既知の制約（起きにくいが、塞いでいない穴）

- install が root を作る前に失敗した場合、その root には `<root>.native-<UTC>` が無い。このとき `migrate-rollback` が backup を戻してから `restored` の行を書くまでの間に中断すると、再実行は backup が無いと判定して「`<root>.bak-<UTC>` is missing」で止まり、続きから再開できない（`restored_but_unrecorded` は `<root>.native-<UTC>` が在ることを条件にしているため）。root は元の場所に戻っているので、実 HOME の状態を見て人が `restored` の行を足す
- `rehearse` は backup に含まれない `~/.apm/apm_modules` を、backup からではなく実 HOME から複製する。backup を取ったあとに実 HOME の `apm_modules` が変わると、rehearsal の複製は backup と同じ時点の状態にならない

### 実 HOME の checkout の移設（手動）

`<HOME>/.apm` が checkout（`.git` か `catalog/` がある）の間は、`migrate` が何も書かずに止まる。実 HOME は 2026-11-10 に切り替え済みで、checkout は `~/src/github.com/jey3dayo/apm-workspace` にある。別の HOME を切り替えるときだけ、この節を使う。

- 移す: checkout を `mv` で動かさず、新しい場所へ clone し直す。`~/.apm` の下には worktree、他セッション、private-skills の repo があるため。clone したあとに `apm_modules/` をコピーし、mise の設定の path を直す。`~/.apm` で動いているセッションを止めてから、旧 `~/.apm` を `~/.apm.checkout-<UTC>` へ移す。`~/.apm/.worktrees` の worktree は、新しい checkout で `git worktree repair` を実行して直す。`<HOME>/.apm` は consumer の状態（`apm.yml`・`apm.lock.yaml`・`apm_modules`・`deployment-receipts`）だけになり、`migrate` が作る。`APM_WORKSPACE_DIR` は mise の設定に足さない。手順の全文は commit `0bcce09` の同じ節にある
- リンクを置き換える: `backup`・`rehearse`・`migrate` が、root の中の壊れたリンクや HOME の外へ出るリンクを名前つきで拒否したときは、1 つずつ中身のコピーに置き換えてから `backup` をやり直す。実体が HOME の中にあるなら、実体へ張り直してもよい（`ln -sfn "$(realpath "$link")" "$link"`）

  ```sh
  link=~/.claude/skills/<name>
  copy="$(mktemp -d)" && cp -RL "$link" "$copy/entry" && rm "$link" && mv "$copy/entry" "$link" && rmdir "$copy"
  ```

- 戻す: `migrate-rollback` で root を戻す。consumer の `~/.apm` を `~/.apm.consumer-<UTC>` のような別名へ移し、`~/.apm.checkout-<UTC>` を `~/.apm` に戻す。clone した checkout は消さない。mise の設定の path も戻す。この状態の HOME（旧経路のまま）を保守する旧ツール（`deploy`・`apply` など）は、この branch には無い。commit `0bcce09` のものを使う

## 実 HOME を切り替える手順

次の手順 B は、切り替えのたびに行う。最初の切り替えも、あとの更新も、同じ手順を通る。

旧経路が配った HOME を最初に切り替えるときだけ、B の前に、checkout を `~/.apm` の外へ移し（上の「実 HOME の checkout の移設」）、Claude Code と Codex のセッションを閉じる。旧いコピーの root（`~/.claude/CLAUDE.md` など）の退避は、旧ツール（commit `0bcce09`。`migrate:roots` は 2026-11-10 に退役した）か手作業で行う。

B. 切り替えのたび（新しい SHA を配るときも同じ）

- B1. `mise run native:plan -- --source-ref <merge 済みの SHA>` で manifest と手順を確かめる。package の pin は merge 済みの commit にする
- B2. `mise run native:backup -- --real-home --backup-dir <新しいディレクトリ>`
- B3. `mise run native:rehearse -- --real-home --backup-dir <同じディレクトリ> --source-ref <同じ SHA> --migrate`。成功で終わり、`result.txt` が `mode=migrate`・`lost=0`・`baseline_skips=0` で、`allowed-lost.txt` の path がその表のものだけで、`dropped.txt` が意図した削除（catalog から外した skill）だけであることを確かめる。checkout を `~/.apm` の外へ移す前に取った rehearsal は使えないので、移したあとに取る
- B4. `~/.cache/apm` と、あれば `Library/Caches/apm` を `<名前>.native-aside-<UTC>` へ移す。Claude Code と Codex のセッションを閉じる
  - 移す理由: 実 HOME の `~/.cache/apm/git/checkouts_v1` には、上流の切れた symlink がある（2026-11-09 の時点）。`migrate --real-home` はこの 2 つも検査し、切れたリンクがあれば何も書かずに止まる。2026-11-09 に実 HOME へ `apply` したときも、`.cache/apm` の中の上流の symlink（同じ checkout の中で切れた相対リンクや、上流の絶対パスのリンク）で止まった。キャッシュの扱いは、直すべき問題として残している
  - キャッシュなので、install が作り直す
  - 戻し方: 作り直された `~/.cache/apm` を別名（`apm.native-regen-<UTC>` など）へ移し、退避した `apm.native-aside-<UTC>` を `~/.cache/apm` に戻す。どちらも消さない
- B5. `mise run native:migrate -- --real-home --source-ref <同じ SHA> --rehearsal <backup>/rehearsal-<UTC>.<suffix>`。表示された stamp を控える
- B6. 確かめる: 配布された skill と agents、`~/.claude/rules/ai-collaboration.md`、manifest 外の skill（private skill、Herdr、agmsg）、agmsg の `db`・`teams` のリンク、`~/.codex/config.toml` と `~/.claude/settings.json` が変わっていないこと。OpenCode は `~/.config/opencode/AGENTS.md`（無ければ `~/.claude/CLAUDE.md`）を読み、切り替えのあとは両方とも無いので、`mise run native:opencode` でガイドを置く（手書きの `AGENTS.md` は上書きしない）
- B7. 問題があれば `mise run native:migrate-rollback -- --real-home --stamp <UTC>`。移したあとの root は `<root>.native-<UTC>` に残る。問題がなければ、`<root>.bak-<UTC>` と `<root>.native-<UTC>` は手で消すまで残る

### 切り替えたあとの更新

切り替えたあとの実 HOME は、`native:apply` を使わない（実 HOME への `native:apply` は拒否される）。新しい SHA を配るときは、上の B（B1 から B7）をやり直す。B3 の rehearsal は、B2 の backup を取り直してから、新しい `--source-ref` で取り直す。2 回目以降の `migrate` は、前回の native の `<HOME>/.apm/apm.lock.yaml` が載せている entry のうち、今回の catalog が配らなくなったものを入れ直さない（`rehearse --migrate` の `allowed-lost.txt` に、その理由つきで出る）。それ以外で APM が配らなかった旧い entry（private skill など）は、前と同じく入れ直す。

## 確かめていないこと

- 外部の依存の install（テストは通信しない）。特に、構造化した形の `nanaism/yomiyasu` が Codex native plugin の経路を通らずに skill として配られるか
- `allowExecutables` の許可が、本物の `github.com/fujibee/agmsg` と `github.com/tt-a1i/archify/archify` で効くか（テストは、同じ形のキーを持つ package を `https://github.com/<owner>/<repo>.git` から git の設定で fixture へ向け直して確かめた）
- 各 tool が実際に rule とガイドを読み込むか
- Linux（`sandbox-exec` が無い）では、通信と書込みを強制的には止めない。テストが守るのは HOME のガードと `env -i` の隔離まで
- Windows（対象外）
