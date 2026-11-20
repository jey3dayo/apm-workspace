---
name: t3-stack
description: >-
  T3 Code 経由で Mac 上の Claude Code / Codex スレッドへコーディングを委任するときに使う。
  スレッド間の引き継ぎ・文脈の受け渡し、スレッドの作り直しもここで扱う
  （steward の運営・交代は t3-steward）。
  外部の担当bot（Muse、Grok Bot）が T3 MCP でスレッドを直接起動する側と、起動された Mac 側の
  ワーカーが作業する側の共通ルール。通常セッション内の委譲判定と model tier は
  orchestrator-worker が正本で、本スキルは T3 という基盤に固有の決まりだけを持つ。
---

# T3 stack

運用は2形ある。単発の委任では、担当bot が T3 MCP でワーカースレッドを直接起動し、完了まで見届けて人間に報告する。継続的に見張る product では、product ごとに常駐 steward を1本置き、steward がメインセッションとして受け付け、子スレッドへ委譲する（steward の運営は `t3-steward`）。T3 Code に注入される公式の orchestration instructions に従い、ここには公式にない決まりだけを書く。公式と食い違う箇所は「公式より優先」と明記したものだけ、このスキルを優先する。

## 役割

- 担当bot: T3 の外にいる bot（Muse、リポごとの Grok Bot 等）。人間との窓口、依頼の受付、優先度づけ、スレッドの起動と追跡、結果の報告、承認待ちの伝達を担う。重い作業は自分では持たず、すべて Mac 側へ渡す。
- steward: product ごとに常駐する T3 内側のメインセッション。人間が T3 で直接指示するのが主で、担当bot 経由の指示も受ける。計画、委譲、検証、報告を担い、重い実装は子へ切る。運営の手順は `t3-steward`。
- ワーカー: 担当bot または steward が起動する Mac 上の T3 スレッド。実装、レビュー、検証、PR 作成を担う。1タスク1スレッドが原則で、作業は自分の worktree の中で完結させる。
- 人間: T3 の画面で承認と進捗を見られる。担当bot 経由の依頼が既定で、人間が T3 で直接スレッドを立てることもある。その場合もワーカー側の決まりは同じ。
- agent 間の指示と連絡は T3 経由を既定にする。

## steward（常駐メインセッション）

steward の運営（状況ファイル、再開条件、子の依頼文と追跡、マージ・stg の権限、引き継ぎ・交代）は `t3-steward` が持つ。本スキルは steward と担当bot の両方が使う共通基盤を持つ。

スレッド一覧の外側 triage（終わったスレッドの settle 候補の抽出と、停滞の通知）の手順は、担当bot 側の共有スキル（Drive `ai-memory/skills/t3-thread-triage.md`、https://drive.google.com/file/d/1Qt9VVblBQfFWEOl_qUZE22wwx7xhmTKB/view ）が正本で、ここには写さない。steward 配下の子は triage の対象外で、子の settle は steward が行う。

## 起動する側（担当bot）の流れ

1. `orchestrator_capabilities` で上限の `runtimeMode` を先に確かめる。上限がタスクに足りなければ起動せず、人間に伝える。上限はトークン発行時に焼き込まれ、後からは上げられない。
2. `t3_thread_launch` で起動する（担当bot の依頼ごとにスレッドを立てる運用は公式より優先）。モデルは `modelSelection` で指定し、`runtimeMode: "auto"` を毎回明示する（トークンの上限が Auto 未満の bot は自トークンの上限値）。`workspaceStrategy` には `{type: "worktree", baseRef: "origin/<対象ブランチ>", startFromOrigin: true}` を指定する。省くと本体の checkout（root）で動いてしまう。未 push の commit に依存する作業ではローカルの base を使い `startFromOrigin: false` にする。
3. 起動したら、スレッドのタイトルとリンクを人間が後で探せるように記録する。サイドバーは手動整列順で新着が浮上しないため、記録がないと人間が探せない。報告するかはその担当bot の決まりに従う。
4. 起動直後に `t3_thread_read` で着火を確かめる。少し置いて read し直しても items が空で idle のままなら初回プロンプトが届いていないので、同じ内容を `t3_thread_send` で再送する。
5. 完了は `t3_thread_wait` / `t3_thread_read` で受ける。wait が途中で切れてもスレッドが死んだとは限らないので、二重起動せず read / wait で再接続する。launch の応答自体が失われたときは、同じ `clientRequestId` で再試行する。
6. 続きの作業（push、PR 作成、レビュー指摘の修正）は同じスレッドへ `t3_thread_send` で送り、worktree と文脈を引き継ぐ。レビューだけは次節のとおり新しいスレッドで頼む。

外部の担当bot は `create_threads` と `delegate_task` を使えない。外部からの委任は launch が正路。T3 の内側のセッションが子を立てるときは逆で、`delegate_task`（`runtimeMode: "auto"` を明示）を使い、`t3_thread_launch` は使わない。ターンの送受信に `t3` CLI（`t3 thread start` / `t3 thread send`）は使わない。CLI 経由は full access で動いたことがある。

## スレッド間の連携と引き継ぎ

T3 の内側では、スレッド同士で読む・送る・文脈を移すことが標準でできる。ただしスレッド同士が自発的に会話するわけではなく、送る側（内側のセッション、または外部の担当bot）が操作して初めて往復する。引き継ぎ資料を別途作る前に、まずこの標準手段で足りないか確かめる。

内側のセッションが使える手段:

- `t3_thread_read`: 他のスレッドの会話を読める。相手の文脈が要るなら、要約を誰かに作らせるのではなく自分で読みに行く。
- `t3_thread_send`: 任意のスレッドへ送れる。`mode: "auto"` は idle のスレッドを起動し、実行中は steer、終了後は queue になる。`freshContext` を付けると相手の文脈をリセットして新しいセッションとして送れる。送り先は自分より広いモードでは動けない。
- `t3_thread_transfer`: 文脈そのものを移す。`fork` は起点（既定は latest stable）から文脈ごと新しいスレッドへ複製する（ターンはまだ走らない）。`merge_back` は同一プロジェクト内の関連スレッドへ文脈を戻す。状態は `status` で確かめる。
- `delegate_task`: 子には `task` 文だけが渡り、親の履歴は渡らない。分離は `isolation`（`worktree` / `shared`）で選び、結果は `task_status` で受ける。
- 対象を探すときは `t3_thread_search`、相手の実際のモデルやモードを確かめるときは `t3_thread_configure` を使う。

外側の担当bot が使える手段は内側と対称ではない（使える操作は bot ごとの接続ガイドが正で、たとえば Muse の接続では `t3_thread_transfer` は許可されていない）。そのため外部から文脈を渡すときは、原則として `t3_thread_read` で読んで `t3_thread_send` で送る手動 relay になる。この非対称を知らずに内側前提の手順を外部へ、外部前提の手順を内側へ持ち込まない。

引き継ぎ方法の選び方:

1. 同一プロジェクト内での作り直し・分岐・後継スレッドへの引き継ぎは、`t3_thread_transfer` の `fork` を既定にする。引き継ぎ資料は作らない。
2. `delegate_task` の子へ渡す文脈は、`task` 文に自己完結で書く。これは引き継ぎ資料ではなく依頼文そのもので、履歴が渡らない以上は省略できない。
3. 要約した資料を作るのは次のときだけにする: 長い履歴を圧縮して渡したいとき、T3 の外（担当bot のチャット、別アプリ、Drive 等）へ渡すとき、人間が読んで判断する材料が要るとき。
4. 続きの作業を同じスレッドへ送るのは引き継ぎではない。`t3_thread_send` で同じスレッドへ送れば文脈はそのまま使える（起動する側の流れの 6 と同じ）。

スレッドの作り直し（MCP の追加などツール構成の変更が目的の場合を含む）:

- まず同じスレッドのセッション入れ替えや開き直しで足りるか確かめる。担当bot の窓口や、スレッドに結びついた予約のような T3 の外の紐付けはスレッド単位で結びついているため、作り直すほど付け替えが増える。
- 作り直す場合は `fork` で文脈を移し、新しいスレッドは同じ名前を引き継ぎ、旧スレッドは旧と分かる名前に変えて settle → archive する（スレッド名の節のとおり）。
- `fork` で移るのは T3 の内側の文脈だけ。窓口の接続先や予約のような外の紐付けは移らないので、作り直した後に付け替え済みか一つずつ確かめる。

## スレッド名

- 常駐 steward は product ごとに1本だけとし、名前は `<product>: steward` に統一する（product はリポの短い名前を小文字で）。
- 日付、`T3`、（常駐管理）のような説明は名前に付けない。日付は引き継ぎの翌日には実態とずれ、`T3` と常駐管理は steward という語自体で分かるため。
- steward を後継スレッドへ引き継ぐときは同じ名前を使い、旧スレッドは settle してから archive する。同じ名前の steward が同時に2本見える期間を作らない。
- ワーカー（子）スレッドの名前も同じ product 接頭辞で始める（例: `<product>: #123 <タスク名>`）。

## 依頼文と分担

- 依頼文には、対象リポ、ゴール、確かめられる完了条件、見せてほしい証拠（変更ファイル一覧、commit、検証結果）、制約を書く。作業合意が固まっている相手には、対象・作業・モデルの effort だけの短い形で足りる。この形が外部の担当bot が launch する T3 経路の契約で、orchestrator-worker の envelope（`source_role` 等）を付ける必要はない。ワーカーは envelope が無いことを理由に止まらない。steward が `delegate_task` で立てる内側の子は例外で、4欄を入れる（`t3-steward`「子の起動と依頼文」）。
- 大きな作業は設計と実装を分ける。設計は Claude Opus（high）の読み取り専用スレッド、実装は Sonnet の後続の別スレッドが既定。レビューは書いたセッションに頼まず、新しいスレッドに読み取り専用で頼み、モデルは Claude Opus か Codex sol にする（T3 経路のレビューは tier 表の Reviewer 既定よりこの指定を優先する）。ただしこの読み取り専用スレッドの結果は advisory で、verdict が要るときは `orchestrator-worker` の `codex exec -s read-only` 経路を使う。具体的なモデル ID は orchestrator-worker の tier 表が正本で、ここには書かない。
- 読み取り専用は依頼文で指示する。`runtimeMode` を絞っても読み取り専用にはならない。
- push と PR 作成は、人間が同じ依頼で求めた場合を除き、別途 OK が出てから行うと依頼文に明記する。担当の決まりで常設の許可があるなら不要。

## リポの範囲と境界

- 既定は個人リポ（`jey3dayo/*`）。
- 会社リポは、人間がそのタスクを明示的に担当bot へ投げた場合に限り対象になる。その場合は止まって境界を蒸し返さず、そのまま起動する。担当bot が自発的に会社リポへ触ることはしない。ただし人間からその担当範囲（リポ）を常設で任されている担当bot は、その範囲の作業なら毎回の明示なしで起動してよい。
- 会社コードを外部のクラウド AI や担当bot 自身の実行環境へ持ち出さない。ワーカーの実行自体は Mac 側の承認済みツール（Enterprise の Claude Code / Codex）で境界の内側にあるが、結果を `t3_thread_read` で読むと返答の内容は担当bot 側へ渡る。会社リポのタスクでは、報告を変更ファイル一覧、PR リンク、要約に限り、コード本文や diff を返させないと依頼文に明記する。担当bot は read で得た内容を外部へ転記しない。

## 権限

- 外部 MCP のトークンは bot ごとに1本で、上限は Supervised（API 値 `approval-required`）から Auto（`auto`）まで。MCP 経由で full access（`full-access`）は要求しない。人間が T3 の画面で直接立てるスレッドの設定は人間の選択に従い、full access を使うのは VM やコンテナで隔離できたときだけにする。
- 子スレッドは親のモードを超えないが、指定しなければ親のモードを受け継ぎうる。T3 の内側で子を立てるときも `runtimeMode: "auto"` を明示し、立てた後に実際のモードを確かめる。
- T3 MCP は Supervised 以上だと全プロジェクトに効き、リポ単位では絞れない。前節のリポ範囲はトークンではなく運用で守る。
- 表示上のモードと実際のモードがずれることがある（pingdotgg/t3code#29632）。画面でモードを変えても、composer から1通送るまでは反映されず、MCP 経由の指示は古いモードのまま動く。モードを変えたら、人間にそのスレッドの composer から1通送ってもらう。実際のモードは `t3_thread_configure`（`threadId` を指定）か read の `runtimeMode` で読む。
- 子の承認要求は T3 の画面に出る。担当bot はそれを押せないので、どのスレッドで何の承認が待っているかを人間へ伝える。権限、購入、予算、ログイン切れ、仕様の分かれ目に来たら、ワーカーは止まって報告し、担当bot は人間にやってほしいことを1つにまとめて伝える。

## worktree のセットアップ

- T3 は worktree 作成時に、リポ直下の `t3.json` で `runOnWorktreeCreate: true` を付けたスクリプト（最初の1つだけ）を setup として実行する。スクリプトには `T3CODE_PROJECT_ROOT`（メイン側の checkout）と `T3CODE_WORKTREE_PATH`（新しい worktree）が環境変数で渡る。
- ただし setup の自動実行は、リンク（MCP relay）経由で起動され full access 未満のスレッドでは起きない（`skipped-for-link`、2026-11-18 実測、T3 本体のソースで確認）。担当bot が起動するスレッドと、steward が `auto` で立てる子スレッドはこれに当たる。setup が走った前提で作業を始めてはいけない。
- そのため、新しい worktree で作業する側は、開始直後に setup の実行済みを確かめ、未実行ならリポの setup スクリプトを手動で実行する。手動実行時は `T3CODE_PROJECT_ROOT` と `T3CODE_WORKTREE_PATH` を自分で設定する。steward は子スレッドへの依頼文にこの一手間を明記する。
- T3 に組み込みの dotenv 同期は無い（公式 Issue #764 は not_planned でクローズ）。env ファイルの受け渡しは setup スクリプトでやる。git-wt 等の外部ツールで worktree を作るときのコピー設定は、T3 が作る worktree には効かない。
- リポ側 setup スクリプトの標準形: メイン側 checkout から、gitignore 対象の env ファイル（dotenvx 管理のリポでは `.env` と `.env.keys`）を symlink で渡す。実ファイルは上書きせず、symlink だけを置き換える。バックアップ類（`.env.*.backup` 等）は渡さない。秘密の値は読まない・出力しない。ツール導入（mise 等）は trust を確認し、未信頼なら install をスキップする（fail-closed、trust は付与しない）。途中で失敗しても worktree 作成自体は止めず、最後は exit 0 で終える。
- `t3.json` はリポにコミットする共有物なので、個人パスやマシン固有の値、秘密そのものは書かない。パスは `T3CODE_PROJECT_ROOT` 経由で解決する。
- agent 経由のスレッドでも env を自動で届ける恒久対策は、git の `post-checkout` フックでやる（2026-11-19 実測で有効化済み）。T3 の worktree 作成は本物の `git worktree add` なので、起動経路によらず発火する。設計は次のとおり。
  - フック本体は個人環境側に1本だけ置く（例: `~/.config/git/hooks/post-checkout`）。有効化は `init.templateDir` 経由で各 clone の `.git/hooks` へ複写する形にし、全域の `core.hooksPath` は使わない（lefthook 等が `.git/hooks` に置く既存フックが読まれなくなり、新規 clone での lefthook 導入も拒否されるため）。リポ側には何も足さない。
  - フックの仕事は env ファイルの symlink コピーだけにする。新規のリンク worktree でのみ、メイン側 checkout の gitignore 対象の `.env` 系ファイル（バックアップ類は除く）を symlink で渡す。ガードは3つ: メイン側 checkout では動かない、worktree に `.env.keys` が既にあれば動かない、メイン側に `.env.keys` が無ければ動かない。実ファイルは上書きせず、`.env` の中身は読まず、常に exit 0 で checkout を壊さない。依存 install や trust の処理はフックに入れない。
  - 既存 clone へは `git init`（再初期化）で template を行き渡らせる。再初期化は既存フックを上書きしない。同名フックが既にある clone（husky 等が管理している場合）は上書きせず、そのフック管理側から本体を呼ぶ形で統合する。
  - mise の trust は現行版（v2026.7.5 以降）ではメイン側 checkout の trust を worktree が引き継ぐので、原則として worktree ごとの対応は要らない。聞かれる場合は `trusted_config_paths` に T3 の worktree の置き場所（既定は `~/.t3/worktrees`）を足す。
  - このフックが入っている環境では、手動実行はフォールバックになる。入っていない環境では、従来どおり開始直後の確認と手動実行が要る。

## ワーカー側の決まり

- 自分の worktree の外を触らない。他のスレッドの作業と混ぜない。
- 新しい worktree では、作業開始前に setup の実行済みを確かめる（「worktree のセットアップ」節）。未実行なら手動で実行してから始める。
- 他のスレッドの文脈が要るときは、`t3_thread_read` / `t3_thread_search` で自分で読みに行く。担当bot や人間に引き継ぎ資料を作らせない（スレッド間の連携と引き継ぎの節）。
- 仕事の終わりは、依頼が求めた場合は開いた PR、それ以外は commit まで進めたうえでの報告か、依頼で定めた報告書。デプロイしない。
- マージは自分ではしない（次節）。レビュー指摘の修正は担当bot が同じスレッドへ差し戻すのが既定で、公式の「小さな指摘は自分で直す」より優先する。自分で抱え込まず、差し戻しを待つ。
- 触らなかったものとその理由（実行契約が変わる等）は、やったことと分けて報告する。

### 報告契約（子 → 担当bot / steward）

子の報告は機械契約で、`dev-progress-report` は使わない（人間向けの報告だけがその形式）。1行目に結果を置く。

- 実装・Verifier（`report_contract: DONE`）: `DONE` か `BLOCKED(<task_id>)`。DONE には、最終 commit の full SHA、変更ファイル、検証コマンドとその実行時の cwd（指定した worktree と分かる出力）、触れていない範囲を載せる。BLOCKED には理由と、再開に要る判断を1つ載せる。
- Verifier は役ではなく Worker の一種で、証拠収集だけを行い、合否を判定しない。報告は証拠の保存先パス（`tmp/<task_id>/`）。
- レビュー（`report_contract: REVIEW`）: 読み取り専用で、対象の SHA を固定し、読んだ SHA を報告へ書く。最終行は `VERDICT: APPROVE` か `VERDICT: REQUEST_CHANGES`（blocking が1件でもあれば後者）。T3 スレッドへの読み取り専用の依頼は依頼文での指示にすぎず実行時に強制されないので、結果は advisory として扱う。verdict が必要なときは `orchestrator-worker` の `codex exec -s read-only` 経路を使う。

## マージとデプロイ

- ワーカーはマージしない。
- 担当bot がマージしてよいのは、人間の常設許可か、そのタスクでの条件付き許可（「レビューが通ったらマージして」等）があり、かつ verdict（`orchestrator-worker` の `codex exec -s read-only` 経路。T3 スレッドの読み取り専用レビューは advisory で代わりにならない）の承認で blocking 0、レビューコメント（bot のレビューを含む）をすべて確認済み、CI 緑、CLEAN のときだけ。`--admin` は使わない。
- レビュー指摘に対応したら、bot のスレッドは対応した側が resolve する。人間のレビュアーのスレッドは勝手に resolve しない。
- steward のマージ権限は担当bot と同じ条件で、範囲は `t3-steward` が持つ。
- デプロイと本番リリースは毎回人間の OK を取る。ただし steward が持つ product の stg への反映は、`t3-steward` が定める常設許可の範囲に従う。

## ブラウザ（chrome-devtools）

- steward が並列に動く product では、ブラウザは `chrome-devtools-mcp` を repo-local で製品別プロファイルにして使う。これが steward 配下の認証付き検証の本線で、ワーカーの実行ランタイム（Claude Code／Codex）を問わず共通にする。実行ランタイム側の Chrome 連携の有無で置き換えない。グローバル宣言は `--userDataDir` が無く全セッションが同じプロファイルを掴むため、同時に Chrome を使えるのは1セッションだけになる（Chromium の SingletonLock による仕様）。設定の正本と手順は `apm-usage` の `references/repo-local-mcp.md`（Parallel Sessions 節）。
- ランタイム側の Chrome 連携（Claude の `claude-in-chrome`、Codex の Chrome アドオン）は、どちらも対話セッションで人間の画面を共有する操作のもので、headless の T3 セッションでは前提にしない。複数セッションの分離も無い。Codex のワーカーにも `claude-in-chrome` 前提の手順を持ち込まない。
- repo-local の製品別プロファイル宣言は、Claude と Codex の両方の配布先（MCP 設定）で効いていることを確認する。片方だけに効いている状態は未完了として扱う。
- ログイン済みページを開く・リロードする・SSR を動かす・コンソール／ネットワーク／ログを確認するのは検証行為であり、資格情報の入力ではない。ワーカーが自分のセッションの chrome-devtools MCP で行う。steward は自分ではブラウザを操作せず、操作は Verifier（Worker）に切って、保存された証拠を読んで判定だけする（`t3-steward`「検証・受け入れ」）。steward が常駐のまま一度開くと、プロファイルのロックが外れないため。
- サインイン状態は、MCP の Chrome で対象 origin を開いて認証を通過できるかで確認する（それが確定になる）。
- プロファイル内のパスワード管理拡張の autofill／パスキー操作はワーカーが行ってよく、資格情報の入力には当たらない（資格情報そのものを知る・打ち込むことはしない）。人間に頼めるのは、プロファイルと origin の組み合わせごとに未ログインのとき（初回とセッション期限切れの両方）に、拡張でも通過できない場合のサインインだけ。対象は製品別プロファイルであり、人間が普段使う Chrome ではない。ログイン済みのページを開く操作は人間に頼まない。
- chrome-devtools のツールが現在のセッションに見えないとき（Claude では ToolSearch で `chrome-devtools` を探しても見つからないとき）は、セッションのツール構成の問題として、新規セッションの作成や開き直しを手配して報告する。人間にページを開かせて代替しない。

### 開始時の確認とロック

- 製品別プロファイルを repo-local に宣言済みの product では、検証を始める前に、掴んだプロファイルの実効値を読んで製品別（`~/.cache/chrome-devtools-mcp/profiles/<product>`）であることを確かめる。実行中の MCP の起動引数か、配布先の MCP 設定を読む。宣言の存在だけで済ませない。既定の共有プロファイル（`~/.cache/chrome-devtools-mcp/chrome-profile`）を掴んでいたら、検証せず `BLOCKED(profile mismatch)` で返す。
- chrome-devtools は最初に掴んだプロファイルをセッション中保持する。実測（2026-11-20）では、idle のセッションはロックを外さず、別セッションは `The browser is already running for <profile>` で失敗する。ロックが外れるのは占有しているセッションを settle／終了したときで、その後は新規のブラウザとして起動し、前のページは引き継がれない。検証が終わった子を settle するまで枠は空かない。
- 掴めなかったときは `BLOCKED(browser busy)` で返す。待機、再試行、既定プロファイルや `--isolated` への切り替えはしない。人間がサインインしている間も、その人がロックの保持者として扱う。

### 証拠の保存

- 専用のタブを新しく開き、page ID を記録する。他のタブや無関係な遷移を挟んだ観測は破棄し、開き直す。
- スクリーンショット、ネットワーク、コンソールなどの証拠は、取得したらすぐ `tmp/<task_id>/` へ保存する。報告は保存先のパスで行い、画面の内容を文章で再現しない。
- production の確認は読み取りだけ。

### プロファイルの現状（2026-11-18 時点）

プロファイルは `~/.cache/chrome-devtools-mcp/profiles/<product>`。全 steward product 分が作成済みで、1Password 拡張（Chrome ウェブストア経由）が導入済みであることを拡張フォルダの出現で確認した。拡張の導入と 1Password のサインインは人間が行った。サインイン状態そのものは、2026-11-18 時点ではエージェント側でまだ確認していない（確認方法は上の箇条書きのとおりで、実利用時の認証通過が確定になる）。

注意：同じプロファイルを通常の Chrome（headed）が掴んでいる間は、chrome-devtools-mcp は `The browser is already running` で起動できない。MCP から使う前に headed のウィンドウを閉じる。

## herdr との併用

- herdr は人間がふだん使うだけで、bot の開発の連絡と作業はすべて T3 に寄せる。
- ペインを閉じる前は毎回人間に確認する（review と runner のペインも例外にしない）。
