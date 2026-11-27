# APM native の配布（単一 mise 入口）

APM CLI は `mise.toml` で指定したバージョンを使います。配布の入口は `mise run native:sync` のみで、plan・backup・migrate rehearsal・migration・OpenCode・doctor を順に実行します。migration は問題のない rehearsal がある場合だけ実 HOME に書き込み、失敗時は退避した root を自動で戻します。

実 HOME は 2026-11-10 に native へ切り替え済みで、authoring の checkout は `~/.apm` の外（`~/src/github.com/jey3dayo/apm-workspace`）にあります。内部 stage は sync の一貫した guard・排他・復旧の仕組みを実装するために残していますが、個別の mise task や手動の配布入口にはしていません。

Issue [#68](https://github.com/jey3dayo/apm-workspace/issues/68) の対象だった catalog 移行、native への切替、旧 writer の退役、`native:sync` への集約は完了しています。[#136](https://github.com/jey3dayo/apm-workspace/issues/136) の design rule は scoped instruction へ移し、[#137](https://github.com/jey3dayo/apm-workspace/issues/137) の model policy は手動配置を続けます。更新手順は「ルールの更新」を参照してください。

動作テストは `tests/native-distribution.bats`（`mise run test:sh` に含まれます）にあります。この checkout の `catalog/` と `manual-skills/` を fixture の git repo に入れ、実 APM で使い捨ての HOME へ配って検証します。macOS では `sandbox-exec` で通信と fixture 外への書き込みを拒否しており、fixture の置き場所は `APM_NATIVE_FIXTURE_ROOT` で変更できます。

## 入口

`mise run native:sync` だけが公開されている native task です。push 済み `main` の確認から backup・migrate rehearsal・実配布・OpenCode・doctor までを通して実行します（手順の詳細は下の B を参照）。

sync と内部 stage は HOME ごとに同じ排他ロックを取得します。sync は backup の前から配布後の確認までロックを保持します。backup と rehearsal も排他用の `<HOME>/.cache/apm-native-operation.lock` を作りますが、配布対象データは書き換えません。このロックファイルは退避対象の `.cache/apm` の外にあり、親の symlink とロックファイルの hard link を拒否します。ロックファイル自体は削除せず、そのロックを継承した全プロセスが終了したときに異常終了時も含めて OS が排他を解放します。別のプロセスが保持中のロックファイルを移動・削除しないでください。

backup の対象（rehearse が複製に再現するもの）は次のパスです。

- `~/.apm/apm.yml`・`config.json`・`apm.lock.yaml`・`deployment-receipts`（APM が配った成果物の所有記録）
- `~/.claude/{skills,agents,rules,commands,CLAUDE.md}`
- `~/.codex/{AGENTS.md,rules}`
- `~/.cursor/{agents,rules,AGENTS.md}`
- `~/.agents/skills`・`~/AGENTS.md`
- `~/.config/opencode/AGENTS.md`
- `~/.gemini/config/{skills,AGENTS.md}`

### consumer manifest の生成と pin

consumer の manifest は、root の `apm.yml` にある `jey3dayo/apm-workspace/catalog#main` と `manual-skills#main` の 2 行を、指定した commit SHA への pin に書き換えて生成します。同じディレクトリの新しいファイルに書き出してからリネームで置き換えます。

`nanaism/yomiyasu/skills/yomiyasu#<SHA>` の 1 行は、構造化した形（`git: nanaism/yomiyasu` / `ref: <SHA>` / `skills: [yomiyasu]` / `targets: [codex, cursor, agent-skills]`）に変換します。targets から Claude を外すのは、APM 0.37+ が plugin 形式の package を user scope で Claude native plugin として扱い、`skills:` の絞り込みがあるものを parked して配らないためです（判断の記録は `docs/package-decisions.md` を参照）。SHA は root の行から読み取り、対応表（`scripts/native.sh` の `EXTERNAL_PACKAGE_MAP`）の行が root になければ render は失敗します。

そのほかの外部依存と MCP はそのまま通します（外部依存はもともと SHA で pin しています）。root の `apm.yml` と `apm.lock.yaml` は変更しません。`--workspace-only` を付けると、この repo の 2 package だけを残します。外部依存ごと除外されるため、yomiyasu の変換も不要です。

配布 pin を sync が自動で進めることはありません。新しい commit を配るときは、必要なら `--source-ref` に新しい SHA を渡します。外部依存の pin はこれまでどおり root の `apm.yml` で更新します。

### 書き込み前の安全ガード

- 既存の `<HOME>/.apm/apm.yml` が描画した manifest とバイト単位で異なる場合は、`apm.yml.<UTC>.bak` に残してから置き換えます。同じ名前があれば番号を付け、既存の `.bak` は上書きしません。
- 生成した root（`~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`・`~/.gemini/config/AGENTS.md`）が APM の目印を残したまま compile のあとに編集されていた場合は、何も書かずに停止します。APM の目印は編集を保護せず compile が上書きしてしまうためです。判定には APM と同じ Build ID の照合（`apm_cli/compilation/build_id.py`）を使うため、APM と同じく末尾の改行だけを足した・消した編集は検出しません。
- 既存の `~/.claude/rules/claude-md-design.md` は rehearsal と migration の前に検査します。移行前の管理元（`f011e52`）、指定した source SHA の生成内容、更新前の consumer lock に記録された同じ path の SHA256 のいずれかと一致すれば許可します。異なる内容やリンクは上書きせず停止します。lock は `scripts/lock-hashes.py` の検証を通った記録だけを使います。既存ファイルがあり、指定 SHA を checkout の Git object から読めない場合も停止します。
- HOME の外を指す symlink、壊れたリンク、または通常ファイルのハードリンクが HOME の中にある場合は、何も書かずに停止します。apm がリンクを通して HOME の外のファイルを書き換えてしまうためで、キャッシュの `Library/Caches/apm` のように配布先より深い場所にも書き込みが発生します。rehearse は実 HOME の 5 つの root（`.agents/skills`・`.claude/skills`・`.claude/agents`・`.cursor/agents`・`.gemini/config/skills`）に壊れたリンクや HOME の外へ出るリンクがあれば、`migrate` と同じ判定（`escaping_link_line`）を使い、複製を作る前にそのリンク名を表示して失敗します。root の外のリンクは複製の中へ向け直し、リンク先がなければ外してそのリンク名を表示したうえで、同じ検査を通してから install します。
- `<HOME>/.apm/config.json` に `default_client`・`prefer_ssh`・`executables` 以外のキーがある場合は、rehearsal と migration の内部 stage が停止します。APM が `temp_dir` などの書き込み先をここから読むためです。`prefer_ssh` は git URL の形式を変えるだけで、`executables` は `apm approve --user` が書く実行ファイルの承認であり、どちらも書き込み先は変えません。キーは APM と同じく JSON としてデコードしてから照合します。
- `<HOME>/apm.yml` がある場合は、rehearsal（実 HOME と複製の両方）と migration が何も書かずに停止します。user scope の APM は `<HOME>/apm.yml` があると executable の許可をそちらから読み込み、`<HOME>/.apm/apm.yml` の `executables.allow` を無視するためです（`apm_cli/security/executables.py` の `exec_trust_context_for_project`）。

### APM 実行環境の隔離

apm は空の環境に必要な値だけを渡して起動します。渡すのは `HOME`・`PATH`・ロケール・Git の設定に加え、対話確認を止める `APM_NON_INTERACTIVE=1` と HOME 内の `TMPDIR`（`.cache/apm-native-tmp`）です。APM は `APM_CACHE_DIR` や `XDG_*`、`TMPDIR` が指す場所にも書き込み（`APM_CACHE_DIR` と `XDG_CACHE_HOME` はテストで確認済み）、Git は token・proxy・askpass を環境から読むためです。

## 切り替えのあとの authoring checkout

`scripts/apm-workspace.sh` は `APM_WORKSPACE_DIR` が未設定のとき、`<HOME>/.apm` に `.git`（linked worktree ではファイル）か `catalog/` があればそちらを、なければこの repo の root（`REPO_ROOT`）を `$WORKSPACE_DIR` に選びます。切り替えのあとは checkout の外から実行しても `validate`・`validate:catalog` がその checkout に対して動作します。`.git` の検査では worktree の `.git` ファイルも通します。

## native と手動の境界

分類の意味は次のとおりです。

- native: APM が配布します。
- 手動（レイアウト）: APM の primitive として置いていないため配布されません。
- 手動（APM 非対応）: APM の仕組みでは扱えません。
- APM 外の補完: `native:sync` が APM の install / compile とは別に配置または保全します。
- first cut の外: 今回の対象には含めません。

| 対象                                                         | 分類               | 手順・理由                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | 確認状況                                                                                                                                                                  |
| ------------------------------------------------------------ | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `catalog/.apm/skills`・`manual-skills/.apm/skills`           | native             | -                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | 観測（使い捨ての HOME で、Claude と `~/.agents/skills` の `SKILL.md` が元と byte 単位で一致）                                                                             |
| `catalog/.apm/agents`                                        | native             | Codex には配りません（`docs/package-decisions.md` の Codex 変換の却下を参照）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | 観測（Claude と Cursor に届き、`~/.codex/agents` は作られない）                                                                                                           |
| `catalog/.apm/instructions/ai-collaboration.instructions.md` | native             | compile が Codex と Cursor の root を書きます。Claude には rule として届きます。手書きの `~/.claude/CLAUDE.md` は残ります                                                                                                                                                                                                                                                                                                                                                                                                                                    | 観測                                                                                                                                                                      |
| root `apm.yml` の外部依存                                    | native             | -                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | CI の `dependency-install` は `apm.yml` / `apm.lock.yaml` 変更時に使い捨て HOME で install 成功を確認済み。native 配布内容と `executables.allow` の実効性は CI では未確認 |
| root `apm.yml` の `mcp:`                                     | native             | migrate の install は `--only apm` のため配りません。migrate が成功したあと、`native:sync` の MCP stage（`apm install -g --only mcp`）が配ります。MCP stage は書く前に `~/.codex/config.toml`・`~/.claude.json`・`~/.gemini/config/mcp_config.json` を `<ファイル>.pre-apm-mcp-<UTC>` へ退避します                                                                                                                                                                                                                                                           | Antigravity への配布は実 HOME の `native:sync` で確認（2026-11-25）                                                                                                       |
| `catalog/.apm/instructions/claude-md-design.instructions.md` | native             | `applyTo` を Claude の `paths` に変換し、`~/.claude/rules/claude-md-design.md` に配ります。Codex の global root には入りません。Cursor には `applyTo` を `globs` に変換した `~/.cursor/rules/claude-md-design.mdc` が生成されますが、常時適用にはなりません                                                                                                                                                                                                                                                                                                  | APM 0.36.1 の使い捨て HOME で確認済み。Claude の `paths` と本文は旧 rule と byte 単位で一致                                                                               |
| `catalog/claude/rules/model-policy.md`                       | 手動（レイアウト） | Claude 専用のまま `~/.claude/rules/model-policy.md` へ置きます。APM 0.35.1 は instruction 単位の `targets: [claude]` を使わず、global instruction にすると Codex・Cursor の root にも入るためです                                                                                                                                                                                                                                                                                                                                                            | APM 0.35.1 の使い捨て HOME で確認済み。手動配置は下の手順で比較して更新                                                                                                   |
| private skills（`private-skills/.apm/skills`）               | first cut の外     | consumer の `~/.apm/skills/` に置けば local content として配られます（PR79 で観測）。同名の catalog skill を上書きできるかは確かめていません                                                                                                                                                                                                                                                                                                                                                                                                                 | 未確認                                                                                                                                                                    |
| Antigravity（`~/.gemini/config/`）                           | native             | skills と compile の `AGENTS.md` を user scope に配ります。MCP stage（`apm install -g --only mcp`）は root `apm.yml` の `mcp:` の server を `mcp_config.json` に書き、書く前に既存の `mcp_config.json` を `mcp_config.json.pre-apm-mcp-<UTC>` へ退避します。`~/.gemini/config/skills` にある APM が配らない entry は、ほかの root と同じ退避と入れ直しで残ります。instructions と hooks は APM の antigravity target が user scope で提供せず、agents と commands は target 自体が持ちません。agy CLI はここを読みますが、IDE / App の読み込み元は未確認です | APM 0.38.1 の実 HOME の `native:sync` で確認（2026-11-25）。agy 1.5.16 の `/skills` と `agy mcp list` で確認                                                              |
| OpenCode（`~/.config/opencode/AGENTS.md`）                   | APM 外の補完       | APM の opencode target は制限付きの agent を受け付けないため targets に入れません。`native:sync` が `sync:opencode` でガイドを配置し、手書きの内容は保護します                                                                                                                                                                                                                                                                                                                                                                                               | ソース（`native-sync.sh` と `sync_opencode_instructions`）                                                                                                                |
| Pi（`~/AGENTS.md`）                                          | first cut の外     | ガイドを手動で置きます。APM に Pi の target があるかは確かめていません                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | 未確認                                                                                                                                                                    |
| host-local の MCP                                            | 手動（APM 非対応） | これまでどおり `mise run setup:mcp:host`（`mise bootstrap`）を使います                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | ソース                                                                                                                                                                    |
| Cursor の `~/.cursor/mcp.json`                               | 手動（APM 非対応） | これまでどおり手動で管理します                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | ソース                                                                                                                                                                    |
| この repo の `.apm/skills`、`optional-skills/`               | first cut の外     | 配布対象ではありません（作業用の bridge と、使う repo が導入する skill）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | -                                                                                                                                                                         |

手動の項目のために新しい同期処理は追加しません。

### ルールの更新

`claude-md-design` は instruction の管理元を変更し、通常の PR と `native:sync` で配布します。配布先が更新前の lock の記録と一致していれば、以前に生成した内容から新しい本文へそのまま更新できます。独自編集や lock の欠落・不正で検査が止まったときは既存ファイルと管理元を比較し、残す編集を管理元へ反映したうえで、既存ファイルを一意な `.bak` 名へ移してから backup と rehearsal を取り直します。APM 単独の install は同名 rule を上書きするため、`native:sync` を使います。旧経路が置いた Codex・Cursor・OpenCode の `rules/claude-md-design.md` は自動削除せず、それぞれの tool が読み込むかは未確認のまま扱います。

`model-policy` の内容は `catalog/claude/rules/model-policy.md` で管理しており、更新するときは次の順で進めます。

1. 管理元の変更を PR で確定し、マージ済みの配布 SHA を確認します。`git show <SHA>:catalog/claude/rules/model-policy.md` で候補を checkout の `tmp/` に書き出します。
2. 配布先 `~/.claude/rules/model-policy.md` があれば `diff -u` で候補と比較します。差分があれば、配布先の独自編集を管理元へ取り込むか既存ファイルだけに残すかを決めます。リンクや同名ディレクトリは上書きしません。
3. 更新する既存ファイルを未使用の `model-policy.md.<UTC>.bak` へコピーして保全します。そのあと候補を配布先へコピーし、`cmp` で候補との一致を確認します。初回は既存ファイルがないことを確認して配置します。

`model-policy` を `.apm/instructions` に移したり、手動コピーを Codex・Cursor の root に追加したりしません。`native:sync` はこの手動 rule を更新しないため、手動更新の実施と native 配布の完了は別々に確認します。

## 既知の問題

- APM 0.35.0 は user scope を `~/.apm` に固定しています。`~/.apm` が checkout だと、実 HOME へ配ったときに checkout が追跡している `apm.yml` と APM が書く `apm.lock.yaml` を書き換えてしまい、`main` の checkout が dirty になって `git pull` が止まります。この状態に戻さないため、`migrate` は `<HOME>/.apm` に `.git` か `catalog/` があるとき、またはこの repo が `<HOME>/.apm` の中にあるときに何も書かずに停止します。`mise run check` は実 HOME の配布先に書かず一時ディレクトリにだけ書くため、切り替えのあとも通ります。
- 2026-11-10 より前の `smoke:catalog` は、実 HOME の `~/.apm/deployment-receipts` に一時ディレクトリの receipt（root が `apm-catalog-smoke.*`）を書いていました。その後は一時 HOME を使うようになり、現在はタスク自体を廃止したため、この経路で receipt は増えません。残っている receipt は native 配布の副作用と取り違えないでください。APM 0.38+ は記録先の root が消えた receipt を install 時に掃除するため、残骸が rehearsal の lost に出るようになりました。そのため rehearsal は snapshot の前に、APM と同じ条件（記録された root が絶対パスで、存在せず、親ディレクトリは残っている）で孤児になった receipt を複製から取り除き、`retired-receipts.txt` にファイル名と記録されていた root を残します。実 HOME 側の残骸は migrate の install で APM が掃除します。
- 目印のない root（旧経路がコピーした `~/.claude/CLAUDE.md`・`~/.codex/AGENTS.md`・`~/.cursor/AGENTS.md`）は、`compile -g --clean` が上書きしません。そのため Claude には古い `CLAUDE.md` と native の rule `ai-collaboration.md` の両方が届きます。古いコピーを退避する `migrate:roots` は 2026-11-10 に退役しました。旧経路のままの HOME で必要なときは、commit `0bcce09` の旧ツールで実行するか、手動で `<名前>.<UTC>.bak` へ移します。

## 実 HOME への切り替えの解き方

2026-11-09 に実 HOME へ一度 apply し、実害が出たため rollback しました（backup した 15 パスは差分 0 に戻りました）。原因は次の 3 つで、`migrate` はそれぞれ次のように対処します。

| 起きたこと                                                                                                                                                                                                                                                                                                                | 対処                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apm install -g --only apm` が旧経路の配った skill のファイルを消し（stale-file cleanup）、同じファイルの書き込みは「no trustworthy local deployment baseline」で飛ばしました。`.agents/skills` に旧経路のファイルが残っていると、Codex native plugin の移行も拒否されました（`apm_cli/install/phases/codex_plugins.py`） | 5 つの root（`~/.agents/skills`・`~/.claude/skills`・`~/.claude/agents`・`~/.cursor/agents`・`~/.gemini/config/skills`）を、install の前に `<root>.bak-<UTC>` へ移します（削除しません）。rules と compile が書く root（`CLAUDE.md`・`AGENTS.md`）は移しません。APM は空の root へ配ります                                                                                                                                                     |
| 旧経路が配った skill のうち manifest にないもの（private skill、Herdr などほかの tool が置いた skill）が、移したあとの root にありませんでした                                                                                                                                                                            | compile のあとに内部の `reinstate_entries` で入れ直します。固定リストは持たず、「`.bak` にあって install のあとの root にない top-level の entry」を戻します。既にあるもの（APM が配ったもの、Herdr や Claude が書き直したもの）は上書きしません。`.bak` の中の symlink が root の外を指すときは、配布先が authoring の checkout に依存しないよう中身をコピーして戻します。root の中を指すものはそのまま戻し、壊れたリンクは列挙して失敗します |
| `nanaism/yomiyasu` は Codex native plugin を持つ package で、root の `apm.yml` の書き方（`owner/repo/skills/yomiyasu#<SHA>`）だと plugin として扱われ、移行が止まりました                                                                                                                                                 | render が構造化した形（`git: nanaism/yomiyasu` / `ref: <SHA>` / `skills: [yomiyasu]` / `targets: [codex, cursor, agent-skills]`）に変換します。SHA は root の行から読み、行がなければ render は失敗します                                                                                                                                                                                                                                      |

`browser-use/browser-harness` は root の `apm.yml` で subdirectory の形（`browser-use/browser-harness/skills/browser-harness#<SHA>`）に pin しており、render はこの行をそのまま通します。repo root の形（`browser-use/browser-harness#<SHA>`）だと APM が上流の repo 全体を skill の置き場へ配り、Codex が plugin の skill として数えてしまうためです。subdirectory の形なら `SKILL.md` と `references/install.md` だけが `.agents/skills/browser-harness` と `.claude/skills/browser-harness` に入ります（`skills:` の絞り込みはこの package では APM が無視するため使えません）。

APM は Codex CLI 0.163.0 だけを受け付けます（`apm_cli/codex_plugins/client.py` の `QUALIFIED_CODEX_VERSION`。上書きする手段はありません）。構造化した形が Codex native plugin の経路を通らずに skill として配られるかは、テストが通信しないため本番の install で初めて確かめます（「確かめていないこと」を参照）。

### bin/ の許可（`executables.allow`）

APM は非対話の install で信頼していない package の `bin/` を配りません。root `apm.yml` の `executables.allow` を管理元とし、render は通常配布のときだけそのまま `executables.allow` として出力します。トップレベルのキーは引用なしの通常形式に限り、未掲載の package、重複、`bin: true` または `mcp: true` 以外は拒否します。

APM 0.36.1 では user scope の `<HOME>/.apm/apm.yml` でも新名の `executables.allow` を読み込み、旧名 `allowExecutables` は読み込まれないことを 2026-11-19 に実測しました。現在の承認は次のとおりです（render の出力形を示しています。root 側の yomiyasu のキーは `nanaism/yomiyasu/skills/yomiyasu` で、下の変換でこの形になります）。

```yaml
executables:
  allow:
    ibelick/ui-skills:
      bin: true
    mattpocock/skills:
      bin: true
    nanaism/yomiyasu:
      bin: true
    nextlevelbuilder/ui-ux-pro-max-skill:
      bin: true
    tt-a1i/archify/archify:
      bin: true
    aqua-voice:
      mcp: true
    chrome-devtools:
      mcp: true
    context7:
      mcp: true
    linear:
      mcp: true
    parallel:
      mcp: true
    sentry:
      mcp: true
```

承認の扱いは次のとおりです。

- キーの変換: render は `EXTERNAL_PACKAGE_MAP` にある package（`nanaism/yomiyasu/skills/yomiyasu`）を `executables.allow` へ出力する際、構造化した repo の identity（`nanaism/yomiyasu`）へ変換します。APM が依存から計算する承認キーと一致させるためです。
- 必須項目と範囲: package の `bin/` は必須であり、承認だけが欠けた場合は render が失敗します。変更するときは `scripts/lib/native-manifest.sh` の必須項目も更新します。MCP server は root `apm.yml` で宣言されているものを承認し、hooks・LSP・canvas は承認しません。`--workspace-only` では外部 package の承認を出力しません。
- 旧名と個人承認: `allowExecutables` は APM で deprecated の旧名です。APM 0.35.1 の user scope は `<HOME>/.apm/apm.yml` で旧名だけを読んでいましたが、0.36.1 では新名 `executables.allow` を読み、旧名は適用されません（2026-11-19 に使い捨て HOME で実測済み。旧名のみでは archify と ui-skills の `bin/` が `gated_pending_approval` で止まり、`apm approve` が移行した新名では配布されました）。配布用の必須分は render が `executables.allow` で書きます。個人環境での追加承認は `apm approve --user` で `~/.apm/config.json` の `executables` に入れて構いません（対話端末で `apm install` が出す `Trust <package>? [y/N]` に `y` と答えても同じです）。この個人承認は bin・hooks・MCP・LSP・canvas の executable primitives すべてを package 単位で制御します。`native:*` の中の `apm` は `run_apm` が `APM_NON_INTERACTIVE=1` を固定で渡すため、質問は出ず警告だけで続行します（`install/phases/integrate.py`）。
- 短いキー形式と内容 pin: 許可のキーは host の接頭辞なしの `<owner>/<repo>[/<path>]` です。APM 0.36.1 までは `github.com/<owner>/<repo>[/<path>]` の形で照合していましたが、0.38.1 ではその形は一致せず、project scope でも user scope でも `bin/` が parked になります（2026-11-25 に使い捨て HOME と一時 project で実測済み。短いキーでは初回 install で配布され、`github.com/` 形では配布されませんでした）。0.38.1 の承認は内容 pin が推奨形で、型だけの承認（`bin: true`）では「not pinned to content」の警告が出ますが配布自体は進みます。`apm approve -g <package>` は短いキーを consumer manifest へ書き、内容 pin を consumer lock へ記録します。ただし render が manifest を毎回書き直すため、配布用の承認は root 側のキーを管理元とし、approve の追記には頼りません。
- default-deny の挙動: このブロックを書くと APM の executable 承認チェックが有効になり、許可していない package の hooks・MCP・LSP・canvas も default-deny になります。install の末尾に `executable primitives parked pending approval` という警告が出るのはこのためで、`~/.apm/apm.lock.yaml` の `exec_status` には `gated_pending_approval` と残ります。該当するファイルがあれば rehearse の `lost` に出ます。
- `--trust-bin` の固定指定: `apm install` には `--trust-bin` を固定で渡します（compile には渡しません）。許可があっても stdout が端末でないと APM は `bin/` を飛ばします（`install/exec_gate.py` の `resolve_bin_skip`）。rehearse は出力を `tee` に渡すため端末にならず、migrate は端末で動くため、付けないと 2 つの結果が食い違います。許可の範囲は `executables.allow` が決めるため、`--trust-bin` で全 package に広がることはありません。

### rehearse --migrate が見ること

`rehearse --migrate` は backup の複製の中で、`migrate` と同じ `migrate_roots`（install の前）と `reinstate_entries`（compile のあと）を通します。end-to-end の確認は backup の複製から行います（空の HOME は使いません）。

snapshot の前に、記録先の root が消えた deployment receipt を複製から取り除きます（通常・`--migrate` の両モード。条件と記録の残し方は「既知の問題」の receipt の項を参照）。receipt は APM が管理する所有記録であり配布内容ではないため、消失として数えません。

消えてよいのは `scripts/lib/native-roots.sh` の `allowed_lost_reason` に書いた allowlist だけです。件数は `allowed_lost=` に出力し、`allowed-lost.txt` にタブ区切りで path と理由を残します。allowlist 以外の消失（`lost=`）が 0 件のときだけ成功します。同じ skill の別のファイルは対象外で、消えれば失敗します。

| path（HOME からの相対）                                                                                                                                              | 理由                                                                                                                                                                                                                                              |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 退避した root の中の、basename が `.apm-pin` のファイル                                                                                                              | pin の目印                                                                                                                                                                                                                                        |
| `.claude/skills/synced` とその下                                                                                                                                     | Claude Code が同期する skill の cache です。動作中の session が migrate の途中で作り直すため、退避した古い root の中身と違うことがあります。古い内容は `<root>.bak-<UTC>` に残ります                                                              |
| `__pycache__` ディレクトリとその下、`*.pyc` ファイル                                                                                                                 | Python のバイトコード cache で、再生成できます                                                                                                                                                                                                    |
| `.agents/skills/<skill>/.codex-plugin` とその下、`.claude/skills/<skill>/.codex-plugin` とその下                                                                     | Codex plugin の目印です。構造化した形の dependency install では配りません                                                                                                                                                                         |
| 5 つの root の top-level の entry で、前回の native の `apm.lock.yaml`（`deployed_files`）に載っていて、今回の root にないもの（catalog から消えた skill）の下の全部 | 前回の native では配られ、今回は配られなかったため入れ直しません（catalog から消えた skill のほか、前回と今回で配る package が違う場合も含みます）。前回の lock がない最初の `migrate` では何も該当しません。entry が今も配られていれば対象外です |

#### 入れ直し・skip・pristine 判定

migrate rehearsal は入れ直した entry を `reinstated.txt`（path と scope）に、名前が同じで中身が古い entry と違うために入れ直さなかったものを `skipped.txt` に書きます。`.apm-pin` を除いて中身が同じものは載せず、`.claude/skills/synced`（Claude Code の同期 cache）も実行時の状態として比べません。migration は同じ 2 つを `<HOME>/.apm/native-migrate-<UTC>.reinstated.txt`・`.skipped.txt` に書き、`skipped.txt` が空でなければ warning を出します。

旧 entry が APM の配ったままなら、置き換えても古い配布が失われるだけで手編集は失われません。この判定は実 HOME で行います（rehearsal の clone や退避した root では symlink が実体化されたり壊れたりして、migrate と結果が食い違うためです）。`rehearse --migrate` は clone を作る前に、`migrate` は root を退避する前に、実 HOME の `<HOME>/.apm/apm.lock.yaml`（更新前の lock）と 5 つの root の top-level entry を比べ、次をすべて満たす entry を「pristine」と判定します。

- entry の下が通常ファイルとディレクトリだけで構成されていること
- ファイル集合と sha256 が、lock の `deployed_file_hashes` における該当 entry 分と過不足なく一致すること（`__pycache__` の名前セグメントを含む path と `.apm-pin` は比較対象外）

pristine の一覧は `<entry><TAB><lock 側の記録のダイジェスト>` の形で rehearsal の `pristine-entries.txt` に残ります。`migrate` は書く前に実 HOME で計算し直し、`pristine-entries.txt` と 1 行でも違えば（rehearse のあとに pristine な entry が編集された、symlink になったなど）何も書かずに停止します。skip 候補のうち pristine なものは `skipped.txt` に載せず、`auto-approved-skips.txt`（migration では `.auto-approved-skips.txt`）に書きます。一覧は rehearse と migrate で一致する必要があり、違えば rollback します。なお、hash の一致が示すのは古い配布内容との一致までで、その内容が今の配布より良いかどうかは示しません。

lock は `scripts/lock-hashes.py` が YAML として読み込みます（`dependencies` の各要素の `deployed_file_hashes` のみを対象とし、行の形には頼りません）。PyYAML は apm 自身の python（`APM_BIN` か PATH の `apm` の shebang、mise の shim なら `mise which apm`、最後に `python3`）のうち import できる最初のものを使います。次のいずれかに当たれば lock 全体を解釈不能とし、警告を 1 行出して pristine を空にします（lock がないときも pristine は空です）。

- YAML として読めない、または PyYAML が使える python がない
- 構造が想定外である（`dependencies` が list でない、`deployed_file_hashes` が mapping でない、値が `sha256:<64 桁の小文字 hex>` でない、キーが文字列でない、同じ mapping 内でキーが重複する、同じ path が違う hash で重複する）
- path が HOME 相対の正規形でない（制御文字・バックスラッシュ・先頭や末尾の `/`・空や `.` や `..` のセグメントを含む）

5 つの root のいずれか、またはその上のディレクトリ（`.claude` など）が symlink のときも pristine は空になり、警告を 1 行出します。どの場合も skip は `skipped.txt` に残り、従来どおり `--allow-skip` が必要です。private skill が catalog の skill と同じ名前で上書きしていた場合は、以前の内容を手動で戻します。

#### dropped・baseline・result.txt

前回の native の lock に載っていて今回配られなかった entry は `dropped.txt` に書き、件数を `result.txt` の `dropped=` に出力します。意図した削除（catalog から外した skill）だけであることを、B3 で `dropped.txt` を読んで確かめます。前回の `<HOME>/.apm/apm.yml` が `--workspace-only` で描画されたかどうかは manifest の `# native-render:` 行に残っており、今回と違えば `rehearse --migrate` も `migrate` も停止します。`migrate` は同じ一覧を `<HOME>/.apm/native-migrate-<UTC>.dropped.txt` に書き、`dropped.txt` と違えば失敗して rollback します。

`apm.log` に `no trustworthy local deployment baseline` が出た場合は失敗します（件数は `baseline_skips=`）。

`result.txt` には `mode=migrate`、`home`、`source_ref`、`workspace_only`、各 step の status、`lost`、`allowed_lost`、`dropped`、`baseline_skips`、`previous_lock=present|absent`（`<HOME>/.apm/apm.lock.yaml` の有無）、`home_apm=checkout|consumer|absent`（`<HOME>/.apm` が checkout か、consumer か、ないか）が入ります。末尾の 2 つの値は backup を取った時点の HOME から `home-state.txt` に記録したものです。`rehearse` は今の HOME と違えば（checkout を移したあとなど）、記録のない旧形式の backup と同じく clone を作らずに失敗します。`migrate` もこれを読み、`previous_lock` と `home_apm` が今の HOME と違えば何も書かずに停止します。checkout を移す前に取った rehearsal は移したあとには使えないため（`home_apm` が `checkout` のままになるため）、移したあとや `migrate` が失敗して consumer の `~/.apm` が残ったあとは、backup から rehearse を取り直します。

### migrate の順序

1. `<HOME>/.apm` が checkout（`.git` か `catalog/`）なら停止します。この repo が `<HOME>/.apm` の中にある場合も停止します。
2. `--rehearsal` の `result.txt` を確かめます。条件は `mode=migrate`、同じ HOME・`--source-ref`・`--workspace-only`、install・compile・入れ直しの status が 0、`lost=0`、`baseline_skips=0`、今の HOME と同じ `previous_lock`・`home_apm` です。1 つでも違えば何も書かずに停止します。
3. 共有 guard（`config.json`、`<HOME>/apm.yml` がないこと、compile のあとに編集された root）と、HOME の外へ出るリンクおよび hard link を検査します。`--home` は HOME 全体を、`--real-home` は APM の書き込み先（退避する 5 つの root、rules、compile が書く root、`.apm`、`.cache/apm`、`Library/Caches/apm`）だけを調べます。tool のディレクトリ（`.claude` など）はリンクのときだけ調べます。
4. `~/.codex/config.toml` と `~/.claude/settings.json` をパーミッションを保ったまま `<HOME>/.apm/native-migrate-<UTC>.untouched/`（owner だけが読める）へコピーし、5 つの root の snapshot を取ります。中身はログに出しません。
5. manifest を書き（差があれば前の manifest を `apm.yml.<UTC>.bak` に残します）、5 つの root を `<root>.bak-<UTC>` へ移して退避一覧を `<HOME>/.apm/native-migrate-<UTC>.txt` に記録します。続けて `apm install -g --only apm --trust-bin`、`apm compile -g --clean`、内部の入れ直しを実行します。入れ直しの前には、5 つの root、その `.bak-<UTC>`、`.apm`、および各 root の親ディレクトリ（`.agents`・`.claude`・`.cursor`・`.gemini`・`.gemini/config`）が HOME の外を指すリンクや壊れたリンクでないことを確かめます。
6. migrate で配布対象から外れた entry（前回の native の lock に載っていて今回は配られなかったもの）の一覧を `<HOME>/.apm/native-migrate-<UTC>.dropped.txt` に書き、rehearse の `dropped.txt` と違えば失敗します。同名 entry の内容が違った一覧（`.skipped.txt`）と、lock の hash で自動承認した一覧（`.auto-approved-skips.txt`）も rehearse の同名ファイルと照合し、違えば同じ自動 rollback で戻します。続けて、rehearse と同じ消失検査を migrate 自身が 5 つの root の before/after の snapshot と同じ allowlist で行い、表にないものが消えていれば失敗します（rehearse のあとに足したファイルを、APM が配り直す skill の中で失わないためです）。検査の範囲は 5 つの root だけで、rehearse が見る `.claude/rules`・`.codex/rules`・compile が書く root などは `migrate` 自身は見ず、rehearse 時点の結果に頼ります。一覧は `<HOME>/.apm/native-migrate-<UTC>.lost.txt` に残ります。最後に、手順 4 の 2 つのファイルが変わっていないか照合します。
7. 5 と 6 のどこかで失敗したら自動で rollback して非 0 で終わります。2 つのファイルが変わっていたときは手順 4 のコピーで元に戻し、migrate が残した内容は `<ファイル>.changed-<UTC>` として残します。成功すると `.untouched/` を消し、UTC の stamp と rollback のコマンドを表示します。

#### rollback とセッションの扱い

rollback（自動実行も、sync が表示する直接コマンドも）が戻すのは 5 つの root だけで、今の root は `<root>.native-<UTC>` に残ります。`<HOME>/.apm/apm.yml`・`apm.lock.yaml`・`deployment-receipts`、rules、compile が書いた root は native が書いたまま残ります。これらを元に戻すには、sync が残した backup と `apm.yml.<UTC>.bak` を使います。どちらも名前が既にあれば何も動かさずに失敗します。

root の移動は record に `moved` を書いてから行い、移し終えたら `done` を足します。rollback は戻した root に `restored` を足すため、途中で止まった rollback は原因を直して同じコマンドをもう一度実行すれば続きから完了できます。`restored` の root は飛ばし、root を戻し終えて `restored` を書く前に止まったときは、`done` があり、`<root>.bak-<UTC>` がなく、root と `<root>.native-<UTC>` がある組を戻し済みとして `restored` を足します。`done` がなく backup もない root は、移す前に止まったものとして触りません。`done` があるのに `<root>.bak-<UTC>` がない（手動で消した）ときは、何も動かさずに停止します。

rollback で旧経路の状態へ戻した HOME は、この branch にない旧ツール（`deploy`・`apply` など）を使って保守します。旧ツールは commit `0bcce09` にあります。

`migrate` の間は Claude Code と Codex のセッションを閉じてください。`~/.codex/config.toml` と `~/.claude/settings.json` が変わると失敗して元の内容を書き戻すため、その間のセッションの書き込みが `<ファイル>.changed-<UTC>` に回ります。この 2 つが symlink なら、復元はリンクを保ったままリンク先へ元の内容を書き戻します。リンク先が HOME の外（dotfiles の repo など）であっても書き戻します（今の実 HOME では通常のファイルです）。

`migrate` が失敗して自動で rollback したあとも、`<HOME>/.apm/apm.yml` は描画された manifest のままで、`~/.apm` は consumer の状態のまま残ります。切り替え前（`~/.apm` が checkout）の状態へ戻すには、下の「実 HOME の checkout の移設」の「戻す」のとおり、consumer の `~/.apm` を別名へ移して `~/.apm.checkout-<UTC>` を戻します。migrate のログにも同じ手順が出ます。

### 既知の制約（起きにくいが、塞いでいない穴）

- install が root を作る前に失敗した場合、その root には `<root>.native-<UTC>` がありません。このとき `migrate-rollback` が backup を戻してから `restored` の行を書くまでの間に中断すると、再実行では backup がないと判定して「`<root>.bak-<UTC>` is missing」で止まり、続きから再開できません（`restored_but_unrecorded` は `<root>.native-<UTC>` があることを条件にしているためです）。root は元の場所に戻っているため、実 HOME の状態を確認したうえで手動で `restored` の行を足します。
- `rehearse` は backup に含まれない `~/.apm/apm_modules` を実 HOME から直接複製します（backup からは複製しません）。そのため、backup を取ったあとに実 HOME の `apm_modules` が変わると、rehearsal の複製は backup と同じ時点の状態になりません。

### 実 HOME の checkout の移設（手動）

`<HOME>/.apm` が checkout（`.git` か `catalog/` がある）の間は、`migrate` が何も書かずに停止します。実 HOME は 2026-11-10 に切り替え済みで、checkout は `~/src/github.com/jey3dayo/apm-workspace` にあります。この節は、別の HOME を切り替えるときだけ使います。

- 移す: `~/.apm` の下には worktree、他セッション、`private-skills` の repo があるため、checkout を `mv` で動かさず新しい場所へ clone し直します。clone したあとに `apm_modules/` をコピーし、mise の設定の path を直します。`~/.apm` で動いているセッションを止めてから、旧 `~/.apm` を `~/.apm.checkout-<UTC>` へ移し、`~/.apm/.worktrees` の worktree は新しい checkout で `git worktree repair` を実行して直します。`<HOME>/.apm` は consumer の状態（`apm.yml`・`apm.lock.yaml`・`apm_modules`・`deployment-receipts`）だけになり、`migrate` が作ります。`APM_WORKSPACE_DIR` は mise の設定に足しません。手順の全文は commit `0bcce09` の同じ節にあります。
- リンクを置き換える: `backup`・`rehearse`・`migrate` が root の中の壊れたリンクや HOME の外へ出るリンクを名前つきで拒否したときは、1 つずつ中身のコピーに置き換えてから `backup` をやり直します。実体が HOME の中にあるなら、実体へ張り直しても構いません（`ln -sfn "$(realpath "$link")" "$link"`）。

  ```sh
  link=~/.claude/skills/<name>
  copy="$(mktemp -d)" && cp -RL "$link" "$copy/entry" && rm "$link" && mv "$copy/entry" "$link" && rmdir "$copy"
  ```

- 戻す: sync が表示した直接の rollback command で root を戻します。consumer の `~/.apm` を `~/.apm.consumer-<UTC>` のような別名へ移し、`~/.apm.checkout-<UTC>` を `~/.apm` に戻します。clone した checkout は消さず、mise の設定の path も戻します。この状態の HOME（旧経路のまま）を保守する旧ツール（`deploy`・`apply` など）はこの branch にはないため、commit `0bcce09` のものを使います。

## 実 HOME を切り替える手順

次の手順 B は切り替えのたびに行います。最初の切り替えも、あとの更新も、同じ手順を通ります。

旧経路が配った HOME を最初に切り替えるときだけ、B の前に checkout を `~/.apm` の外へ移し（上の「実 HOME の checkout の移設」）、Claude Code と Codex のセッションを閉じます。古いコピーの root（`~/.claude/CLAUDE.md` など）の退避は、手作業（`<名前>.<UTC>.bak` へ移す）か commit `0bcce09` の旧ツールで行います。`migrate:roots` は 2026-11-10 に退役してこの branch にはないため、`0bcce09` を checkout した clone（authoring の checkout とは別に作成）を用意し、セッションを閉じたまま B の前に次を実行します。

```sh
APM_WORKSPACE_DIR=<0bcce09 の clone の絶対パス> bash <0bcce09 の clone の絶対パス>/scripts/apm-workspace.sh migrate:roots --apply
```

checkout を `~/.apm` の外へ移したあと最初の `migrate` までは `~/.apm` がないため、旧ツールのガードは `APM_WORKSPACE_DIR` を明示しないと拒否します。

B. 切り替えのたび（新しい SHA を配るときも同じ）

通常の更新は、push 済みの checkout で `mise run native:sync` を実行します。local HEAD と配布元の `main` が同じ SHA で、作業ツリーに未コミット変更がないことを確認してから B1〜B7 を順に進めます。毎回新しい backup と migrate rehearsal を作り、キャッシュは削除せず別名へ移します。配布後は OpenCode のガイドを配置し、doctor と intake の確認を行い、5 つの root の top-level entry 数を配布前後で表示します。既存セッションを閉じる操作は行いません。OpenCode の出力先は対象 HOME の `.config/opencode/AGENTS.md` に固定されており、継承した `APM_OPENCODE_OUTPUT` は使いません。配置前には親ディレクトリの symlink とガイドの symlink・hard link を拒否します。

rehearsal に `dropped.txt` や `skipped.txt` の entry がある場合は、実 HOME を書き換える前に停止します。表示されたレポートを読み、意図した削除だけを `--allow-drop <root>/<entry>`、内容の異なる同名 entry の置き換えだけを `--allow-skip <root>/<entry>` で指定して再実行します。どちらのオプションも繰り返し指定でき、実際の一覧と完全に一致する場合だけ続行します（余分な指定は拒否します）。

- 旧 entry が更新前の lock の hash と全ファイル一致する pristine な entry は手編集がないため、`skipped.txt` に載らず `auto-approved-skips.txt` に出るだけで、`--allow-skip` は不要です（付けると余分な指定として拒否されます）。この判定は実 HOME で行い、`migrate` の前に再計算して rehearsal と照合します。root や上のディレクトリが symlink のときは対象外です。sync は件数と一覧のパスを表示します。
- `.claude/skills/synced` も実行時の状態として比べないため、`--allow-skip` は不要で、付けると余分な指定として拒否されます。
- `allowed-lost.txt` は既存の allowlist と照合し、allowlist 外の消失や deployment baseline の省略は指定で許可できません。

GitHub の SSH URL を HTTPS へ向けたいときは `mise run native:sync -- --https` を使います。既存の Git 設定ファイルは変更せず、実行専用の config に HTTPS 用の URL ルールを先に置いて既存の system・global 設定を include します。config は checkout の `tmp/native-https/` に残し、参照する環境変数をこの実行と子プロセスだけへ渡します。配布元 URL が HTTPS へ解決されることも実通信前に確認します。SHA を明示する場合は `--source-ref <SHA>` を指定します。指定した SHA も local HEAD と配布元の `main` の両方に一致する必要があります。

backup・rehearsal・各段階のログは checkout の `tmp/native-sync/<UTC>.<suffix>/` に残ります。失敗した段階で停止し、migration が出力した stamp と対応する record を一意に確認できた場合だけ、`bash scripts/native.sh migrate-rollback --real-home --stamp <UTC>` の形で直接の rollback command を表示します。stamp を確認できない場合は、ログを調べてから復旧します。cache の退避先もあわせて表示されます。

sync が実行する B1〜B7 は次のとおりです。これらは 1 回の `mise run native:sync` の中で動く内部 stage であり、個別の task としては公開していません。

- B1. merge 済み SHA の manifest と手順を plan log に出します。
- B2. 非秘密の対象の新しい backup を作ります。
- B3. backup の複製で migrate rehearsal を実行し、`mode=migrate`・`lost=0`・`baseline_skips=0`、`allowed-lost.txt`、`dropped.txt`、`skipped.txt` を検証します。
- B4. `~/.cache/apm` と、あれば `Library/Caches/apm` を `<名前>.native-aside-<UTC>` へ移します。
  - 移す理由: 実 HOME の `~/.cache/apm/git/checkouts_v1` には上流の壊れた symlink があります（2026-11-09 の時点）。`migrate --real-home` はこの 2 つも検査し、壊れたリンクがあれば何も書かずに停止します。2026-11-09 に実 HOME へ `apply` したときも、`.cache/apm` の中の上流の symlink（同じ checkout の中で壊れた相対リンクや、上流の絶対パスのリンク）で止まりました。キャッシュの扱いは直すべき問題として残しています。
  - キャッシュのため、install が作り直します。
  - 戻し方: 作り直された `~/.cache/apm` を別名（`apm.native-regen-<UTC>` など）へ移し、退避した `apm.native-aside-<UTC>` を `~/.cache/apm` に戻します。どちらも消しません。
- B5. 同じ SHA と B3 の rehearsal で migration を実行し、stamp を記録します。
- B6. OpenCode のガイドを配置し、doctor と intake を実行して配布前後の entry 数を表示します。手書きの OpenCode `AGENTS.md` は上書きしません。
- B7. 問題があれば sync が表示した直接の rollback command を実行します。移したあとの root は `<root>.native-<UTC>` に残ります。問題がなければ、`<root>.bak-<UTC>` と `<root>.native-<UTC>` は手動で消すまで残ります。

### 切り替えたあとの更新

新しい SHA を配るときは、毎回 `mise run native:sync` で新しい backup と rehearsal を作ります。2 回目以降の migration は前回の native の `<HOME>/.apm/apm.lock.yaml` に載っている entry のうち、今回の catalog が配らなくなったものを入れ直しません（rehearsal の `allowed-lost.txt` に理由つきで出ます）。それ以外で APM が配らなかった古い entry（private skill など）は、前と同じく入れ直します。

## 確かめていないこと

- native 配布後に外部依存が各 tool へ届く内容と、各 tool が rule・guide を読み込むかどうか。CI は `apm.yml` / `apm.lock.yaml` の変更時に使い捨て HOME で `apm install -g --only apm --trust-bin` の成功を確認しますが、native 配布先の内容は確認しません。
- 許可の実効性は CI では自動確認しません。CI probe は `--trust-bin` を使うため install の成功しか見ません（本物の `tt-a1i/archify/archify` で短いキーの `executables.allow` が適用されることは、APM 0.38.1 の使い捨て HOME と一時 project で 2026-11-25 に実測済みです）。Bats は同じ形のキーを持つ package を `https://github.com/<owner>/<repo>.git` から git の設定で fixture へ向け直して確かめます。
- 構造化した形の `nanaism/yomiyasu` が Codex native plugin の経路を通らずに skill として配られるかどうか。
- Linux（`sandbox-exec` がない環境）では、通信と書き込みを強制的には止めません。テストが守るのは HOME のガードと `env -i` の隔離までです。
- Windows（対象外）。
