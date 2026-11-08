# モデルの評価と選定理由

`orchestrator-worker` の tier 表・Reviewer の tier・Worker の昇格表が、なぜそのモデルを選んでいるかの根拠。どのモデルを使うかの規則は SKILL.md が正本で、ここには規則の理由と、表どおりにいかないときの手順だけを置く。

## モデルを更改するとき

agmsg-delegation の helper の allowlist が各 provider から取得したモデル一覧（Codex は fetched_at 付きのローカル cache）に載っているかは `~/.apm` の `mise run models:check` で確認する。

- MISSING: 取得した一覧に未掲載。直ちに直す
- NEWER: 同系列の新しい版がある。原則として helper の allowlist と tier 表を新しい版へ上げる（価格帯が変わる場合だけ確認する）
- RETIRING: 廃止予告（Codex の retirement_at または一覧から隠されたモデル / opencode の deprecated）。後継へ切り替える

tier 表と helper の allowlist の一致は、各 helper の bats テスト（`script allowlist matches the orchestrator-worker tier table`）が見る。表だけ、または helper だけを書き換えるとテストが落ちる。

## Codex Sol の版と代替

本文で推奨する `gpt-6.1-sol` がアカウントや client で利用できない場合、または応答前に `server_overloaded` が返る場合は、skill 起因と判断せず、利用可能なら model picker / 設定で旧版 `gpt-6-sol` を明示選択して再試行する。自動 alias や fallback は行わない。利用可能モデルはアカウントと client により異なるため、[公式モデル一覧](https://learn.chatgpt.com/docs/models)を参照する。

旧版 `gpt-6-sol` を Reviewer で選べないのは、cached input 単価が `gpt-6.1-sol` の2倍（5 vs 2.5 credits/1M、他の単価は同じ）だからである。helper は Reviewer の `gpt-6-sol` を exit 2 で拒否する。

## Reviewer の選定理由

terra は Sol より安く、レビューの既定に据える。価格差が大きく、読む量が多いレビューでも長文脈リコールが Sol に近いため（下の「長文脈」）。Sol より下の帯だが、terra は high にしても割に合わないと報告されているため medium に留める。

`gpt-6-astra` を明示指定のときに限るのは、Sol より上の帯で価格も能力も上だからである。

Fable reviewer は Orchestrator 側の Fable rate limit と枠を共有するため、実行中 429 で run ごと失敗しうる。

## Worker の昇格の理由

難度が理由のときに Terra を中間段として挟まないのは、Terra が Sol より安く弱く、昇格の 3 条件に対しては Sol より弱い段を 1 つ増やすことになるためである。挟んで足りなかったときに払うのは価格差ではなく、タスク 1 本分の作業と Orchestrator の再検証がもう一周ぶんである。「Terra では難度に足りない」という実測があるわけではなく、失敗した 1 周のコストが価格差より大きいという判断による。

昇格先の価格を本文にもここにも固定しないのは、変わりやすく、古い値で選ぶと昇格の判断を誤るためである。Luna が安いことは無制限であることを意味しない——どの tier も共有クレジットプールと利用上限を消費する。

`gpt-6-astra` を Worker の昇格先にしないのは、実装トークンを安い Worker へ隔離するという本スキルの目的が反転するためである。

opencode には昇格先の上位 tier が無い。昇格表の opencode 行で Codex Luna 経路へ出すのは、tier を上げる昇格ではなく経路差し替えである。`--variant max` で足りなかった場合も同じ扱いになる。cursor 行の昇格先 `claude-opus-5-5-high` は、tier 表 Reviewer 行と同じ model へ揃えている。

## 長文脈

長文脈タスク（大規模コードベースの読解、複数文書の統合、長い履歴の追跡）で Terra を選ぶのは、能力不足を補うためではなく、Sol とほぼ同等の長文脈リコールを Sol より安く買うためである。`luna` は長文脈リコールに崖があり（5.6 世代の計測: MRCR 41.3% / Sol 91.5% / Terra 89.6%、[OpenAI](https://openai.com/index/gpt-5-6)。gpt-6 世代は未計測）、effort 引き上げで緩和されるという実測は公表されていない。

昇格表で opencode 行と cursor 行の長文脈を対象外にしているのは、どちらも長文脈リコールが未計測だからである。
