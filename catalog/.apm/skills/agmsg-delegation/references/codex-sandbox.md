# Codex sandbox

Codex worker / reviewer を起動する際の sandbox 挙動、profile 運用、既知の制約をまとめる。呼び出し元は `agmsg-delegation` の Preflight（`references/codex-sandbox.md` を先に読む）。

## review profile

agmsg 経由の Codex review（helper の review role と pane 常駐 reviewer）に `--sandbox read-only` を使ってはならない。agmsg を使わない `orchestrator-worker` の verdict review は送受信を伴わないため `-s read-only` で起動し、その起動と受理は `orchestrator-worker`「Reviewer の tier」が正本。agmsg の送受信自体が DB 書込み（`send.sh` の messages.db 更新、`inbox.sh` の read_at 更新）と report 一時ファイル作成を必要とするため、完全 read-only では reviewer が READY/REVIEW/ACK を送信できない。代わりに、agmsg 状態ディレクトリ（db/teams/run）だけを `writable_roots` に持つ profile `agmsg-review`（`CODEX_HOME/agmsg-review.config.toml`）を `-p` で layer する。**`writable_roots` は symlink 成分を含むと Codex が exec を拒否する**（"symlinked writable roots are not supported"）。`~/.agents/skills/agmsg/db`・`teams` は `~/.local/state/agmsg/` への symlink なので、profile には canonical path を列挙する（列挙内容は profile 正本のコメントを参照）。

profile の正本は本スキルの [agmsg-review.config.toml](../agmsg-review.config.toml)（tracked asset）。**Codex の `-p` は profile ファイルが欠落していても exit 0 で base config にフォールバックする（fail-open）ため、`run-codex-worker.sh` が起動前に正本を解決済みの `$CODEX_HOME` 直下へ `install -m 600` で置き直し、その後 `cmp` で一致を検証する**。spawn 経路では `$CODEX_HOME` が実行ごとに生成する worker home（`mktemp -d` 配下）を指すため、置き場所は `~/.codex` 直下ではない。手で pane を立てる常駐経路ではこの置き直しが走らないので、起動前に自分で `cmp` を通す（[resident-pool.md](resident-pool.md)）。`CODEX_HOME` は APM の配布面ではないため（`targets:` は runtime 種別のリストで、skills / agents ディレクトリと `~/.codex/AGENTS.md` しか配布しない）、この置き直しが catalog 正本への追従経路になる。

- spawn 経路では手動コピーは不要。catalog 側の profile を更新したら、`docs/native-distribution.md` の B で配り直すだけでよい（手起動 pane は上記のとおり自分で `cmp` を通す）
- source が欠落、コピー失敗、コピー後も不一致のいずれでも helper は起動を拒否する（fail-closed）

## worker 専用 CODEX_HOME と MCP allowlist

base config を複製して plugin・非 allowlist の MCP・`notify` を落とした home を毎回作り、実行後に消す。auth は symlink で共有する。`-c mcp_servers.X.enabled=false` では `config.toml` に節を持たない plugin 由来のサーバを止められない（`-c plugins."x@y".enabled=false` は codex 0.153.2 で無視されることを実測済み）ため、home ごと分ける。

base の他の設定（`openai_base_url`、`service_tier`、`sandbox_workspace_write`、`projects` の trust）はそのまま残るので、閉じるのは MCP と plugin だけになる。allowlist の既定値と上書き変数は `run-codex-worker.sh` が正本。

## cwd をスクラッチへ逃がす理由

**profile の `sandbox_mode = "workspace-write"` は cwd を必ず書込可能にする。** そのため `run-codex-worker.sh` は review role で **cwd を専用スクラッチ（`mktemp -d`）へ逃がし**、対象 project を cwd にしない。project へは read のみで到達でき、payload が絶対パスで指示する。スクラッチは git repo でないので `exec --skip-git-repo-check` を併せて渡す。`writable_roots` に対象 project を足してはならない。足すと read-only 契約が黙って壊れる。

## writable_roots の symlink fail-closed 検査

**`run-codex-worker.sh` は起動前に `writable_roots` の symlink 成分を検査して fail-closed する。** 不正な root が1つでもあると Codex は sandbox 構築自体に失敗し、**agmsg と無関係なコマンドまで起動前に全拒否する**。worker 側からは「シェルすら起動できない」形にしか見えず、原因が設定にあると分からないまま停止する。検査対象は role で異なる。

- implement: profile を layer しないため `CODEX_HOME/config.toml` の base config を検査する
- review: profile の `writable_roots` は base config を**置換**する（実測済み）ため、配置後の profile だけを検査する

検査に引っかかった場合は該当 root・ファイル・canonical path へ直す指示を名指しで出して exit 1 する。

## launchd の MISE_ENV 継承

launchd 経路では親の `MISE_ENV` が継承されず、node を必要とする mise 管理の npm wrapper が即死することがある。
`launch-worker.sh` は `MISE_ENV` を wrapper に引き継ぎ、同じ npm install 配下の `vendor/*/bin/codex` native binary を優先する（無ければ node の PATH を補完する）。
同じ理由で、helper が読む上書き変数 `AGMSG_WORKER_EFFORT` / `AGMSG_REVIEWER_EFFORT` / `AGMSG_WORKER_MCP_ALLOW` / `AGMSG_OPENCODE_VARIANT` も、親で空でなく設定済みのものだけを wrapper に引き継ぐ。
effort と variant の値は各 helper が検証し、`AGMSG_WORKER_MCP_ALLOW` は検証せず許可リストの照合にそのまま使う。`MISE_ENV` / `PATH` / `AGMSG_CODEX_BIN` と上の 4 変数以外の環境変数は launchd job に引き継がれない。

## pane で Codex worker を起動するときのサンドボックス選択

常駐プールの pane はユーザーが手で起動するが、実装 worker の通常経路は既存 worktree を使う sandboxed pane とする。orchestrator またはユーザーが pane の起動前に worktree を作成し、pane worker は次で起動する:

```bash
codex -m <Worker モデル ID> -a never -s workspace-write
```

モデル ID は `orchestrator-worker` の [モデル対応表](../../orchestrator-worker/references/models.md)から選ぶ。

起動後、orchestrator は pane の実 cwd と `git worktree list --porcelain` を照合し、`git -C "$worktree" rev-parse --show-toplevel` と `git -C "$worktree" branch --show-current` が指定した worktree / branch と完全一致することを確認する。さらに開始時点の `git status --short` / `git diff` と worker 後の差分を比較し、タスク定義にない unexpected diff がないことを確認する。

worktree の事前作成ができない場合だけ、外部隔離された別の one-shot `--yolo` session に作成を限定する。その session は worktree の作成直後に終了し、実装は必ず新しく起動した上記 sandboxed pane worker に続けて渡す。実装 worker を `--yolo` のまま常駐させない。

scoped `--add-dir` は worktree 作成の代替にならない。workspace-write は `git worktree add` が書く Git の管理ファイル（refs の lock、target の `.git`）を保護するため、`.git` を追加しても `Operation not permitted` で止まる。従って `--yolo` は外部隔離された worktree 作成の one-shot session に限り、作成後は直ちに終了させる。

`--yolo` は `--dangerously-bypass-approvals-and-sandbox` の別名で sandbox 自体を無効化する。外部隔離された one-shot の worktree 作成以外では使わず、承認プロンプトで停止させない目的だけなら `-a never` で足りる。

`-a` の有効値は `on-request` と `never` のみ。`on-failure` は存在しない（0.149.1 で確認）。

`writable_roots` に symlink 成分があると Codex は sandbox 構築ごと失敗し、agmsg と無関係なコマンドまで起動前に全拒否される。詳細は上記「writable_roots の symlink fail-closed 検査」を参照。

## linked worktree での workspace-write

**Codex の `workspace-write` sandbox は、linked git worktree の gitdir（main repo の `.git/worktrees/<name>`）を read-only に保護する。** 親の `.git` や `.git/worktrees` を `writable_roots` へ追加しても read-only 保護は解除されない。この設計により、worktree 内で `git add` / `git commit` が `Operation not permitted` で失敗する（Codex CLI 0.167.1 on macOS、2026-11-10 検証）。

    70|### 回避策: `--add-dir` による gitdir 書込許可

worktree 内で Codex を起動する場合、起動時に gitdir を明示的に書込可能へ追加する:

```bash
codex exec --add-dir "$(git rev-parse --path-format=absolute --git-dir)" -- <command>
```

`--add-dir` で渡す gitdir は absolute path でなければならないため、`--path-format=absolute` を必須とする。この flag を付けることで、worktree 内での `git add` / `git commit` が成功する。**`codex exec --worktree` だけでは不足**で、gitdir への書込許可が別に必要。
80|
参考: [Codex sandbox guide](https://developers.openai.com/codex/sandbox), [GitHub issue #14338](https://github.com/openai/codex/issues/14338)

### 非対話 codex exec での stdin block 回避

非対話モードで `codex exec` を実行する場合、stdin からの入力待ちで無期限に block される問題がある（[GitHub issue #20919](https://github.com/openai/codex/issues/20919)）。回避策として、**stdin を `/dev/null` から redirect する**:

```bash
codex exec <args> < /dev/null
```

    90|

さらに、外部 timeout でプロセス全体を wrap して、予期しない block への最終保護とする:

```bash
timeout 300s codex exec <args> < /dev/null
```

### セキュリティ注意: hooks への書込可能化

**gitdir を `--add-dir` や `writable_roots` で書込可能にすると、`.git/hooks` も書込可能になる。** エージェントが hooks を変更すると、以降の git 操作で任意コードが実行される。**エージェントは決して hooks を変更してはならない**。

同様に、`$HOME` やリポジトリ root 全体を `writable_roots` へ追加することは禁止する。意図しない範囲への書込を許可し、`.git/hooks` / `~/.config` / `~/.ssh` など機微なファイルへの意図しない変更を招く。

### 便利: worktree 用 wrapper (optional)

一部環境では、linked worktree 内で自動的に gitdir を `--add-dir` 経由で渡す個人 helper `codexw` が利用可能である。worktree 外では plain `codex` と同じ動作をする。これは optional convenience であり、常に generic equivalent も機能する:

```bash
# wrapper (optional, personal dotfiles helper)
codexw exec -- <command>

# generic equivalent (always works)
codex exec --add-dir "$(git rev-parse --path-format=absolute --git-dir)" -- <command>
```

非対話形式:

```bash
# wrapper (optional)
timeout 300s codexw exec <args> < /dev/null

# generic equivalent (always works)
timeout 300s codex exec --add-dir "$(git rev-parse --path-format=absolute --git-dir)" <args> < /dev/null
```
