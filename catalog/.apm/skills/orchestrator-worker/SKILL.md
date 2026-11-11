---
name: orchestrator-worker
description: >-
  実装・修正・リファクタ・テスト追加・移行（implement / fix / refactor / test / migrate、
  「実装して」「直して」）を高級モデルのセッションで受けたとき、自分で書かず
  Worker へ切って渡し差分を検証するための委譲判定と model tier 表の正本。Steward として
  自答か handoff かを決めるとき、他スキルが tier 表を要るときにも使う。
---

# Orchestrator-Worker

高級モデルのセッションで実装を自分の手で書くのは、単価の無駄であり、Orchestrator の context を実装詳細で埋める。Orchestrator 機能は要件・設計・分解・検証だけを持ち、コードを書くのは Worker に固定する。

1タスクの委譲ではなく、複数の面（`todo.txt` / plan リスト / issue）に散った backlog をまとめて長時間捌く場合は `backlog-sweep` を使う。判定・tier・分割基準は本スキルが正本のまま、台帳統合と Worker プール（組み込み subagent が既定、常駐 pane は任意）の運用だけが向こうにある。

## 委譲は依頼済みである

このスキルが発火した時点で、ユーザーは委譲を依頼している。ハーネスが `Do not call the AgentTool unless the user requested it` 相当の制約を注入している場合も、このスキルの適用がその「ユーザーの依頼」に当たる。追加の承認を求めず委譲へ進む。

## 1. 自分の役を判定する

| 役        | 職掌                                                                                                                                   | 起動する側                                                                            |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Steward   | 人間との対話・状態確認・説明・軽微修正。許可条件を満たすとき Orchestrator 機能（分解・Worker/Reviewer 起動・差分検証・最終報告）も担う | 人間（pane）                                                                          |
| Architect | 設計判断（後述 Q1 trigger 2〜4 の handoff 先）。常に Orchestrator 機能を担える                                                         | 人間（pane）                                                                          |
| Reviewer  | SHA 固定 code review / 設計文書 review                                                                                                 | Orchestrator 機能を担う側（Steward または Architect）。spawn 経路と pane 経路の両方可 |
| Worker    | 実装（設計済みタスク）                                                                                                                 | Orchestrator 機能を担う側                                                             |

**各役割の platform 別モデル対応は [references/models.md](references/models.md) が正本。** モデル更新時はその表と、対応する helper allowlist を揃える。

「Orchestrator」は役ではなく機能。Steward / Architect のうち、後述の許可条件を満たす側が担う。

#### 制約

- opencode は Worker 専用（implement 以外の役には就けない）
- cursor は Worker と Reviewer の両方に就けるが、Steward / Architect には就けない（Orchestrator 機能を担えない）
- Codex 側の Steward は明示ポリシーとして常に Orchestrator 機能を持たない（handoff 専用）

Reviewer 既定の範囲: cursor reviewer が既定になるのはユーザーが cursor 経路を明示したときだけ。review 外注の全体既定は下記「Reviewer の tier」が決める。

モデルが使えないとき、`server_overloaded` が返ったとき、選定理由を確かめるときは [references/models.md](references/models.md) を読む。

### 自己判定規則（本文から推測しない）

役は受け取ったメッセージの envelope で決まる。本文の口調からは判定しない。

役を決める前に envelope を検証する。次のいずれかに当たったら `BLOCKED(task_id)` を返す（対話セッションならユーザーへ報告して停止）:

- agmsg 経由で必須 field（`source_role` / `target_role` / `task_id` / `report_contract`）のいずれかが欠けている
- `target_role` と `report_contract` が対応表に反する
- どちらかの値が対応表に無い

| 役                  | `report_contract` |
| ------------------- | ----------------- |
| Worker              | `DONE`            |
| Reviewer            | `REVIEW`          |
| Steward / Architect | `HANDOFF`         |

検証を通ったら役を決める（上から順に、最初に当たったところで止める）:

1. envelope に `target_role` がある → その役
2. `target_role` が無く、`task_id` + `report_contract` だけがある → 対応表の逆引き
3. envelope が無い対話セッション → 起動時に宣言された default role。宣言が無ければ、自分のモデルが Steward の許可集合に入るなら Steward、入らないなら Architect

envelope の必須フィールドと書式は `agmsg-delegation` の「envelope」節が正本。

ack 不要と最終結果不要を混同しない。`HANDOFF` で受けた作業は、終わったら送り手へ返す。

### 役が決まったら許可集合を検証する（fail closed）

役を確定したら、**自分のモデルが [references/models.md](references/models.md) の該当する役割・platform 行に載っているか**を確認する。載っていなければその役を引き受けない:

| 受け取り方     | 不一致のときの動作                                              |
| -------------- | --------------------------------------------------------------- |
| task 契約      | `BLOCKED(task_id)` を返す（自分のモデル名と要求された役を記載） |
| handoff        | 適切な許可集合を持つ役へ handoff し直す                         |
| 対話セッション | ユーザーへ不一致を報告して停止                                  |

### Orchestrator 機能を担う条件（機械的）

次の 3 つをすべて満たすこと:

- 依頼を §3 の粒度（触るファイル / 完了条件 / 検証コマンド）へ自分で分解できる
- 固定した成果物（SHA / checksum で対象を固定した差分）を自分で検証できる
- DoD（format / lint / typecheck / test の該当範囲）を自分で実行できる

tier は能力とコストの属性であり、検証の独立性とは別の軸。同一モデルでも別 session・別 context なら独立した観測者になり得るが、上位モデルでも設計者自身の self-review は独立にならない。「Worker より上の tier」を許可条件に使わない。

- Opus Steward、Architect（Fable / Opus / sol / terra）: 上記 3 条件を満たす。実装依頼は自分で §3 分割 → Worker 起動 → §5 検証 → 人間へ最終報告
- Sonnet Steward: Opus advisor が利用でき 3 条件を満たす場合、Orchestrator 機能を担える。設計判断は advisor に相談し、Worker・Reviewer の選定と成果物の検証は本スキルに従う。advisor が利用できない場合は Architect へ handoff
- Luna Steward: 明示ポリシーとして Orchestrator 機能を持たず handoff 専用。実装依頼は Architect へ handoff。軽微修正（§1a の応答範囲内）は自分で行う
- Worker が親と同じモデルへ昇格した場合: 親は coordination を継続してよいが、最終 acceptance は作者と異なる identity かつ別 session の Reviewer を必須とする。同一 identity・同一 session による自己承認は成立しない

最終報告は依頼が来た経路へ返す。人間から直接受けた側は人間へ、Steward の handoff で受けた Architect は Steward へ handoff 書式で返す。Steward と Architect はどちらも人間が pane から起動する前提。

完了条件: 自分がどの役かを言語化できている。

## 1a. Steward の応答範囲と handoff

Steward は人間が最初に話す相手。どの Steward が Orchestrator 機能を担えるかは §1「Orchestrator 機能を担う条件」に従う。

### 自分で答えてよい範囲（Q2）

- 1ファイルの軽微修正、typo、設定値の変更
- 調査・探索のみで編集を伴わず、下記トリガー 4 の bounded scan で範囲が閉じるもの
- 既存の決定・仕様・スキル・設定の説明
- 状態確認と操作の代行: `git status`、inbox、pane 状態、`--help`、事実照会、図・表の読解

§2 は Worker への委譲可否を扱う。Steward の設計・方針決定は Q1 に従う。

### handoff するトリガー（Q1）

次のいずれか 1 つに当たったら handoff し、どれにも当たらなければ自分で答える（判定順は上から）:

1. 書込を伴い、§2 の委譲条件に当たる（3 ファイル以上 / 見積 50 行以上 / 独立サブタスク 2 件以上）: 自分が Orchestrator 機能を担う側なら handoff せず自分で §3 分割 → Worker 起動 → §5 検証。handoff 専用と定めた Luna Steward、または advisor が利用できない Sonnet Steward なら Architect へ handoff
2. 「Worker の昇格」の 3 条件のいずれか（再現困難なデバッグ / セキュリティ境界 / 複数案のトレードオフ判断）→ handoff
3. 成果物が「決定」である: 依頼文が、ファイル構成・責務境界・API・データ構造・運用方針のうち 1 つ以上を新たに決めることを求めている。既存の決定の説明は Steward が自分で答える → handoff
4. 最初の bounded scan で範囲が閉じない: 入口・ownership・依存だけを一度 scan し、(a) 複数の ownership boundary をまたぐ統合が要る (b) 新しい責務・API・運用判断を決める必要がある (c) 初期 scan の想定より範囲が広がった、のいずれかなら → handoff
5. 委譲しない例外に当たる（権限・認証・秘密情報・破壊的操作・production 変更）→ Steward は触らず handoff。Orchestrator 機能側が自分で扱う

判定不能なときは人間に 1 問だけ聞くか、既定で handoff。既定を handoff 側へ倒す理由: 過剰 handoff のコストは「1 回の handoff メッセージ」に留まるが、過小 handoff のコストは「安いモデルの設計判断がそのまま実装される」ことで非対称だから。

自分のモデルが Architect の許可集合にも入る Opus の単独セッションでは、トリガー 2〜5 と判定不能時も handoff せず Architect として自分で答える。トリガー 5 は global の停止・確認ポリシーに従い、人間へ確認する。Opus advisor が利用できる Sonnet の単独セッションはトリガー 2〜4 だけを同様に扱い、設計判断は advisor に相談する。

「単独」は宣言で判定する。起動時に default role が宣言され、かつこの作業用の Architect pane も宣言されている場合だけ handoff し、それ以外は単独セッションとして扱う。

人間が「執事で答えて」「アーキテクトへ」と明示したら、それが上記トリガーによる判定を上書きする。

handoff は `agmsg-delegation` の引き継ぎ書式で Architect pane へ送るか、その書式を添えて人間へ返す。実行中の session のモデル変更ではなく、逆方向（Architect から Steward）は定義しない。

### agent / skill 定義側のモデル割り当て

- 各 agent のモデルは `catalog/.apm/agents/*.agent.md` の frontmatter `model:` に書く
- Orchestrator 役はメインセッションが担い、agent 化しない
- 判断の結果が本番反映・承認・却下に直結する agent は `model` を指定せず親モデルを継承させる（read-only の triage も含む）
- スキル定義の `model:` は、fork 実行され末端で完結し、手順が固定され判断を含まないものにだけ書く（`atomic-commit` / `apm-deploy-verify` / `docs-manager` / `polish`）。`context: fork` が無いと `model:` は親のそのターンの残り作業まで降格させるため、`context: fork` + `agent:` + `background: false` を併記してサブエージェントだけに効かせる。fork 側は会話履歴を見ずユーザーにも確認できないため、対象は引数と git 状態から決め、判断は親へ返す

## Reviewer の tier

通常のレビュー・相談は、セッションと同じ runtime の組み込み subagent（Claude は Agent tool、Codex は `spawn_agent`）を既定にし、作者と別 context で起動する。実行時の read-only 境界を証明できない結果は advisory として扱う。verdict を必要とするレビュー（`ship` の非軽微な変更など）は、作者と別の新規セッションで起動する `codex exec -s read-only`（下の「verdict review の起動と受理」）を既定にする。`agmsg-delegation` の review は任意の代替経路で、使うときは同 skill の受理条件にも従う。差分を書いた runtime と別 runtime の Reviewer は、追加の脱相関が必要なときだけ選ぶ。

**Reviewer のモデル選定は [references/models.md](references/models.md) が正本。** 既定の格と、判断の難度で上げる先、明示指定時の格がある。

組み込み subagent の Claude reviewer は強制 read-only 境界の証拠を残せないため、結果は advisory に留まる。Fable reviewer が実行中に 429 で失敗したら同経路で再試行せず、opus か Codex reviewer へ切り替えて再外注する。

### verdict review の起動と受理

verdict review は、対象 repo を `-C` で渡し、次の flag をすべて付けた新規の `codex exec` で起動する:

```sh
codex exec --ephemeral --ignore-user-config --ignore-rules \
  --disable hooks --disable plugins --disable apps \
  -c 'mcp_servers={}' -s read-only \
  -m <Reviewer-model-ID> -c model_reasoning_effort=<effort> \
  -C <対象 repo> --json - < <prompt ファイル> > <ログ> 2>&1
```

モデル ID と effort の既定値は [references/models.md](references/models.md) を参照。

- `-s read-only`: model が生成する shell コマンドと `apply_patch` の書込みを、repo の内外とも sandbox で拒否
- `--ignore-user-config`: `$CODEX_HOME/config.toml` の MCP・plugin・hooks・projects trust を読まない（auth は `CODEX_HOME` のまま）
- `--disable hooks` / `plugins` / `apps` と `-c 'mcp_servers={}'`: 既定で有効な hook・plugin・apps を止め、MCP サーバを空にする
- `--ignore-rules`: sandbox 外の実行を許す execpolicy の `.rules` を読まない
- `--ephemeral`: セッションを残さない

prompt には固定したレビュー対象（適用元 `HEAD` の SHA と diff ファイルの絶対パス・checksum）を書き、その diff ファイルだけをレビュー対象にすること、読んだ diff ファイルの checksum と `HEAD` の SHA を報告に書くことを指示する。diff ファイルは、その経路の強制境界が reviewer の書込みを拒否するパスに置く。`codex exec` 経路では prompt・diff・ログを対象 repo の外に置く。`agmsg-delegation` 経路で拒否されるパスを選べない場合は verdict にしない。

verdict は、経路によらず次の共通条件をすべて満たした場合だけ受理する:

1. 作者と別 identity・新規 session・別 context で起動している
2. 固定した SHA と diff checksum が、prompt に書いた値・reviewer が報告に書いた値の両方と一致する。終了後は、実際の `HEAD` が固定 SHA と一致すること、diff ファイルの checksum を再計算して固定値と一致すること、実ツリーからレビュー対象 diff を再生成した checksum も一致することを確かめ、`git status --short` と `git ls-files --others --exclude-standard` も開始時と一致する。レビュー対象に未追跡ファイルを含む場合は、その内容も固定・照合する
3. 正常終了し、経路の形式で明示的な verdict と findings が返っている

経路ごとに次も満たす:

- 上の `codex exec` 経路
  - 起動側が `codex --version` と起動引数をログに残し、使用中 version の公式文書・help で上の flag の対応を確認する。`codex --disable hooks --disable plugins --disable apps features list` で3つが false であること、起動引数に全 flag が揃うこと、ログに MCP・子 agent の実行がなく正常終了していることを確かめる
  - sandbox や迂回経路の制約に影響する起動設定を変更した場合、または書込み成功・無効化した経路の実行など境界異常の具体的な証拠がある場合だけ、当該経路の verdict 受理を保留し、原因を確認して境界を再検証する。version 更新やログ形式変更だけでは再計測を必須にしない
  - verdict は最後の行の `VERDICT: APPROVE` か `VERDICT: REQUEST_CHANGES`。blocking 指摘が1件でもあれば REQUEST_CHANGES とする
- `agmsg-delegation` の review 経路: 同 skill の「7. 報告を受けて検証する」の review 受理条件（`review_mode: verdict` と起動前の強制境界の証拠を含む）をすべて満たし、verdict は同 skill の形式に従う

境界の診断には `scripts/measure-readonly-sandbox.py` を使える。

条件が欠けた結果は advisory とし、出荷工程の通過根拠にしない。ファイル sandbox は外部サービスへの操作を制限しないため、prompt には外部への書込みをしないことも書く。

### self-review 禁止（approval gate）

Architect / Worker が作成した成果物の **approval gate は、作者と異なる identity かつ別 session / 別 context の Reviewer を必須とする。** 同一 pane / 同一 identity での兼務は、草案レビューや相談までに限定し、approve を受理しない。

対象の同一性（SHA / checksum の固定）と判断の独立性（作者と別の reviewer であること）は別々の要件。SHA を固定しただけの self-review は approval gate を通過しない。

Reviewer は組み込みの subagent（Claude は Agent tool、Codex は `spawn_agent`）で起動するのを既定にし、その結果は advisory として扱う。verdict が要るときは「verdict review の起動と受理」の `codex exec` を使う。pane 常駐の Reviewer や agmsg の helper を使うときは `agmsg-delegation` の経路を使う。

## 2. 委譲するか決める

次の順序で判定する。

自分で処理する:

- 1ファイルの軽微修正、typo、設定値の変更
- 調査・探索のみで編集を伴わないもの
- 設計判断が未確定、またはユーザーとの対話が必要なもの

上記に該当せず、次のいずれかを満たすなら委譲する:

- 3ファイル以上の編集、または見積 50 行以上の差分
- 独立して進められるサブタスクが 2 件以上ある
- 設計方針が確定していて、実装手順を文章で書き下せる

完了条件: 委譲する / しない のどちらかを、上の条件を根拠に宣言した。

「設計方針が確定している」は並列タスク間でも成り立つ必要がある。2 つのタスクがそれぞれ同じ規約（命名、エラーの形、型の設計）を自分で決めなければ実装できないなら、方針はまだ確定していない。対処は直列化ではなく、その規約をタスク文に書いて渡すこと。

## 3. 最小単位へ切る

委譲前にタスクを分割する。切り方の判定基準は 2 つ:

- 触るファイル集合が互いに素であること。2 つのタスクが同じファイルを編集するなら、統合するか直列に並べる
- タスク単体で検証できること。そのタスクだけで通せる test / typecheck / lint を指定できる粒度まで割る

互いに素にできない編集を並列で走らせる場合に限り、Claude 側は Agent tool の `isolation: "worktree"` を使う。

「触るファイル」には指定した検証コマンドが書き換えを強制する対象まで含める。設定値を変えるなら、その値を固定値で assert しているテストも同じタスクに入る。全依存を無制限に洗い出すのではなく、変更する契約に直結する設定とテストまでを追い、起動前にタスク定義と対象テストを実際に読む。読んでも見つからなかったファイルが後から必要になった場合、Worker は `BLOCKED` を返す。

同じ tree で並列に走らせる Worker には、scratch の出力先も「触るファイル」として互いに素に割り当てる。タスク文に `tmp/<task_id>/` のような Worker ごとの置き場を must で書く。

assert が業務契約なのか実装詳細なのかは Orchestrator が判断する。テストを機械的に新実装へ合わせさせない。

「検証コマンド」は、そのタスク単体で通す focused gate と、Orchestrator が横断で回す統合 gate を区別して渡す。隔離 worktree には gitignore 済みの `private-skills` なども無い。実ツリーでの配布確認は統合 gate に入れ、Orchestrator が主ツリーで回す。共通の境界を変えるタスクは、focused gate にその境界を縛る architecture / boundary テストを含める。検証コマンドは、先に repo の `mise` task と CI の定義から実コマンドを確認して写す。独自のフラグを足すときは理由を書き、その失敗は repo の gate との差として扱う。worktree の Worker には、検証コマンドごとに実 cwd が指定した worktree だと分かる出力を報告へ含めさせる。

回帰修正で修正前の失敗を証明する場合は、共有 checkout を切り替えずに[固定SHA fixtureを隔離](references/regression-fixtures.md)する。

並行して別セッションが同じ tree を触りうる場合は、独立性の確認に開始時点の差分と所有範囲を含める。Worker が自分の成果と他者の変更を区別するための情報であり、dirty があるだけで一律に停止させない。意図した base は full SHA へ固定し、その SHA を branch / worktree 作成の start-point として明示的に渡す。共有 tree での切り替えは並行させない。

完了条件: 各タスクについて「触るファイル」「完了条件」「検証コマンド」の 3 点が書けている。完了条件には、満たすべき振る舞いと満たさない反例を書く。タスク文では must の制約（外部契約・責務境界・永続データ構造・安全境界・複数タスク共通の規約）と任意の実装例を区別して示す。Worker は must の範囲内で手段を選び直してよく、その場合は理由を報告する。ただし must 側を変える必要が出たら、実装せず矛盾の根拠を親へ返す。

## 4. Worker を起動する

Claude:

```text
Agent(subagent_type: "implementer", prompt: <タスク定義>)
```

通常委譲では `model` を渡さない。呼び出し時の指定は agent 定義の frontmatter より優先されるため、渡すと `implementer` に設定済みの既定 tier を上書きしてしまう。

Claude セッションで Codex モデル（`luna` / `terra` / `sol` / `astra`）を指定された場合、Agent tool は使えない。この場合は `agmsg-delegation` の spawn 経路へ切り替える。やむを得ず別の経路や tier を採るときは、起動前に差し替え先と理由をユーザーへ報告し、最終報告にも記す。

Codex:

Codex では `spawn_agent` からモデルを明示指定できる。モデル上書き時は `fork_turns: "none"` を使い、leaf worker として実装だけを担当させる。子には collaboration tools が公開されないため、再帰的な委譲・分解・検証は Orchestrator 機能側が担う。`multi_agent_v2 = false` での V1 固定や `model_catalog_json` の上書きは使わない。

Codex native の `spawn_agent` を標準経路とする。native spawn が利用できない環境、別セッション・別プロセスへの引き継ぎ、または native runtime の制約を回避する必要がある場合だけ `agmsg-delegation` へ切り替える。worker の reasoning effort は既定 `xhigh`。別プロセス起動の手順・境界・片付けは `agmsg-delegation` の Lifecycle が正本。

### Worker の昇格

次のいずれかを含む Worker タスクに限り、既定 Worker から昇格させる:

- 難しいデバッグ（再現困難、原因未特定）
- セキュリティ境界に触る変更、セキュリティレビュー
- 複数案のトレードオフ判断を含む実装

**昇格先は [references/models.md](references/models.md) が正本。** 理由が「難度」か「長文脈」かで行き先が変わる。opencode と cursor で別経路へ送るのは昇格ではなく経路差し替えで、§4 の契約どおり差し替え先と理由を起動前と最終報告で明示する。

昇格先が現在のモデル自身になる場合も、**親 session がそのまま実装しない**。同じモデルの Worker を別 identity・別 session として起動する。§5 の照合は成果物を独立に確かめることを前提にしており、起動側と実装側が同一 session だとその前提が崩れる。別 session を確保できない場合は `BLOCKED` とし、Architect へ handoff する。

昇格先を選ぶ際は [公式 rate card](https://help.openai.com/en/articles/20001106-codex-rate-card) で現在の価格を確認する。

Claude では独立タスクを同一レスポンス内で複数呼び出すと並列に走る。Codex では `spawn_agent` で worker を複数起動する。どちらも触るファイル集合が互いに素であることが前提。どちらも Orchestrator の会話履歴は引き継がせず、Section 3 で書き出した 3 点だけを渡す。

起動後の扱い:

- バリアを置かない。先に返った Worker から順に処理する
- Worker を使い回す。追加指示・スコープ縮小・再実行は、新規 spawn ではなく既存 Worker への追送で行う（Claude は `SendMessage`）。Codex（agmsg-delegation 経由）は worker が headless 1 turn で終了する契約のため使い回せない
- Codex native の spawn 枠が詰まったら、新規 spawn 前に agent の状態を確認し、目的に合う完了 Worker を再利用する。再利用先が無い場合は不要な完了 agent だけを閉じ、稼働中の無関係な agent は終了させない

1つの依頼を subagent 調査とレビューの反復で仕上げる運用は `review-fix-loop`、複数の plan・台帳をまとめて消化するのは `backlog-sweep` を使う。

完了条件: 全タスクが Worker へ渡り、独立タスクは並列で起動している。

## 5. 受け取って検証する

受入判断と最終報告の各主張を、固定した成果物と実行結果へ照合する。Worker の `verified` は独立確認の入力であって、Orchestrator 自身の推論を保証しない。

- `git status --short` と `git diff` を自分の目で読み、実際の差分を確認する
- untracked ファイルは `git ls-files --others --exclude-standard` で列挙し、各ファイルの内容も検証する
- worktree の Worker を受け取るときは、主 checkout の `git status --short` も実装前後で比べる
- タスク定義に無い変更が入っていないか確認する
- タスク横断で衝突がないか確認し、全体の test / typecheck を通す
- DoD の該当項目を満たす

主張の広さと検証の広さを一致させる。最終 tree が健全だと言うなら最終 SHA を確認すれば足りるが、途中の各 commit も成立すると言うなら各 commit を確認する。「参照が残っていない」と断定するなら、その主張が覆う集合を検索する。1 ファイルを見て全体を語らない。

ファイル・コマンド・タスクの不存在を根拠にするときは、global の共有ガイダンスの「事実確認」に従う。一覧コマンドの出力に無いことは、存在しないことの証明にはならない。

完了条件: 確認した対象・確認結果・未確認のまま残した範囲を対応させて報告した。

## 委譲しない例外

権限・認証・秘密情報の操作、破壊的操作、production への変更は Orchestrator 機能側が自分で扱う。

外部公開（リリース・publish・deploy）は、手順が確立していて機械的に実行できるものなら Worker へ委譲してよい。ただし次を満たすこと:

- 実行前に Orchestrator 機能側が対象バージョン・手順・影響範囲を確認する
- 結果の検証（公開されたことの確認）も Orchestrator 機能側が自分で行う
- 依頼した範囲を、選ぶ実行経路の権限で実際に実行できること。委譲してよい（policy）と実行できる（runtime）は別。境界は role と base 設定が決め、モデルを替えても越えられない。`agmsg-delegation` 経路の照合は同 skill の Preflight に従う

手順が未確立、または判断を伴う公開は自分で扱う。実効境界の外だと分かった場合は、既に権限を持つ経路か Orchestrator 自身へ戻す。指定されたモデルと異なる経路を採るときは §4 のとおり差し替えを明示する。この委譲許可は、worktree 外書込み禁止と Worker の commit / apply 非自動化を解除せず、組み込み subagent にも同じ境界を適用する。
