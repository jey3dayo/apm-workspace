# モデル ID 対応表と選定理由

`orchestrator-worker` の各役割に対応する具体的なモデル ID の正本。役割と格の規則は SKILL.md が正本で、ここには具体的なモデル ID と、選定理由と、表どおりにいかないときの手順を置く。

## 役割ごとのモデル対応

### Steward（執事）

| platform | モデル ID         | 備考                                           |
| -------- | ----------------- | ---------------------------------------------- |
| Claude   | `sonnet` / `opus` | Opus advisor 併用が既定。Opus も可             |
| Codex    | `gpt-6-luna`      | 明示ポリシーとして Orchestrator 機能を持たない |

### Architect（設計者）

| platform | モデル ID                                                         | 備考               |
| -------- | ----------------------------------------------------------------- | ------------------ |
| Claude   | `fable` / `opus`                                                  | どちらも可         |
| Codex    | `gpt-6.2-astra` / `gpt-6.2-sol` / `gpt-6.1-sol` / `gpt-6.1-terra` | `gpt-6.2-sol` 推奨 |

### Reviewer（レビュアー）

| platform | モデル ID                                                               | effort | 備考                                                                                                                                         |
| -------- | ----------------------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude   | `fable` / `opus`                                                        | —      | fable 既定、fallback opus                                                                                                                    |
| Codex    | `gpt-6.1-terra` / `gpt-6.1-sol` / `gpt-6.2-sol` / `gpt-6.2-astra`       | medium | terra 既定。難度高は `gpt-6.1-sol` へ上げ、必要なら effort も上げる。`gpt-6.2-sol` は候補のみ。astra は明示指定時のみ。旧版 `gpt-6-sol` 不可 |
| cursor   | `claude-fable-5-2-xhigh` / `claude-opus-5-5-high` / `gpt-5.6-sol-xhigh` | —      | cursor 経路を明示したときだけ使い、fable を既定とする                                                                                        |

T3 Code 経由のレビューは本表の既定より `t3-stack` の指定（Claude Opus / Codex sol）が優先する。

### Worker（実装者）

| platform | モデル ID                                                      | effort           | 備考                                      |
| -------- | -------------------------------------------------------------- | ---------------- | ----------------------------------------- |
| Claude   | `sonnet` / `opus` / `haiku`                                    | —                | sonnet 既定、昇格 opus、機械的検証 haiku  |
| Codex    | `gpt-6-luna` / `gpt-6.2-sol` / `gpt-6.1-sol` / `gpt-6.1-terra` | xhigh            | luna 既定。難度昇格 sol、長文脈昇格 terra |
| opencode | `deepseek/deepseek-flash`                                      | `--variant high` | Worker 専用                               |
| cursor   | `claude-sonnet-5-5-high` / `claude-opus-5-5-high`              | —                | sonnet 既定、昇格 opus                    |

### Worker の昇格先

| platform | 既定 Worker                                | 難度で昇格                                                     | 長文脈で昇格                         |
| -------- | ------------------------------------------ | -------------------------------------------------------------- | ------------------------------------ |
| Claude   | `sonnet`                                   | `opus`                                                         | —                                    |
| Codex    | `gpt-6-luna` xhigh                         | effort を max へ → `gpt-6.2-sol`（利用不可時は `gpt-6.1-sol`） | `gpt-6.1-terra`                      |
| opencode | `deepseek/deepseek-flash` `--variant high` | 経路差し替え（Codex Luna 経路へ）                              | 計測まで対象外（Codex Terra 経路へ） |
| cursor   | `claude-sonnet-5-5-high`                   | `claude-opus-5-5-high`                                         | 計測まで対象外（Codex Terra 経路へ） |

## モデルを更改するとき

版付きモデル ID を変える場所はこのファイルだけである。他のスキル・agent・`catalog/claude/rules/model-policy.md` は `sonnet` / `opus` 等のエイリアスで書く決まり（リポの AGENTS.md）なので、版が上がっても触らない。ランタイム側に helper の allowlist がある場合は、この表と揃えるのが mirror 側の作業になる。

照合先は provider ごとに決まっている。汎用の検索結果や他 provider の一覧で代用しない。

| 対象         | 照合先                                                                        |
| ------------ | ----------------------------------------------------------------------------- |
| Claude       | [Claude Models overview](https://platform.claude.com/docs/en/models/overview) |
| OpenAI API   | [OpenAI API Models](https://developers.openai.com/api/docs/models)            |
| Codex client | [Codex Models](https://developers.openai.com/codex/models)                    |
| cursor の行  | [Cursor Models & Pricing](https://cursor.com/docs/models-and-pricing)         |

手順は次のとおり。

1. 上の照合先で現行ラインナップを確認する。Codex client の推奨ページは API カタログより反映が遅れることがあるため、API 側の版を正とし、client 側で使えない場合の代替は「Codex Sol の版と代替」に従う。
2. 同系列の新しい版がある場合は、価格帯が変わる場合を除き tier 表を更新する。廃止予定または一覧から外れたモデルは後継へ切り替える。
3. cursor の行は Cursor 独自のモデル名で照合する。API カタログに合わせて書き換えない（例: 2026-11-24 照合時点で Cursor の OpenAI 最新は GPT-5.6 系で、`gpt-5.6-sol` は現行。API の GPT-6.2 系は Cursor 一覧に無い）。
4. 更新したら、この節末尾の最終照合日を当日に書き換える。

最終照合: 2026-11-24（Claude Fable 5.2 / Opus 5.5 / Sonnet 5.5、OpenAI GPT-6.2 Astra / Sol・GPT-6.1 Terra・GPT-6 Luna、Cursor GPT-5.6 Sol を各照合先で確認し、tier 表と一致）

## Codex Sol の版と代替

本文で推奨する `gpt-6.2-sol` がアカウントや client で利用できない場合、または応答前に `server_overloaded` が返る場合は、skill 起因と判断せず、利用可能なら model picker / 設定で `gpt-6.1-sol` を明示選択して再試行する。自動 alias や fallback は行わない。利用可能モデルはアカウントと client により異なるため、[公式モデル一覧](https://learn.chatgpt.com/docs/models)を参照する。

旧版 `gpt-6-sol` を選ばないのは、cached input 単価が `gpt-6.1-sol` の2倍（5 vs 2.5 credits/1M、他の単価は同じ）だからである。

## Reviewer の選定理由

terra は Sol より安く、レビューの既定に据える。価格差が大きく、読む量が多いレビューでも長文脈リコールが Sol に近いため（下の「長文脈」）。Sol より下の帯だが、terra は high にしても割に合わないと報告されているため medium に留める。high 以上の terra は 6.2 Sol に負ける（AA v5.0.1: terra high 42点 $0.26・xhigh 45点 $0.40 / 6.2 Sol medium 53点 $0.41）。

`gpt-6.2-astra` を明示指定のときに限るのは、Sol より上の帯で価格も能力も上だからである。

Fable reviewer は Orchestrator 側の Fable rate limit と枠を共有するため、実行中 429 で run ごと失敗しうる。

## Worker の昇格の理由

難度が理由のときに Terra を中間段として挟まないのは、Terra が Sol より安く弱く、昇格の 3 条件に対しては Sol より弱い段を 1 つ増やすことになるためである。挟んで足りなかったときに払うのは価格差ではなく、タスク 1 本分の作業と Orchestrator の再検証がもう一周ぶんである。「Terra では難度に足りない」という実測があるわけではなく、失敗した 1 周のコストが価格差より大きいという判断による。

昇格先の価格を本文にもここにも固定しないのは、変わりやすく、古い値で選ぶと昇格の判断を誤るためである。Luna が安いことは無制限であることを意味しない——どの tier も共有クレジットプールと利用上限を消費する。

`gpt-6.2-astra` を Worker の昇格先にしないのは、実装トークンを安い Worker へ隔離するという本スキルの目的が反転するためである。

opencode には昇格先の上位 tier が無い。昇格表の opencode 行で Codex Luna 経路へ出すのは、tier を上げる昇格ではなく経路差し替えである。`--variant max` で足りなかった場合も同じ扱いになる。cursor 行の昇格先 `claude-opus-5-5-high` は、tier 表 Reviewer 行と同じ model へ揃えている。

## 長文脈

長文脈タスク（大規模コードベースの読解、複数文書の統合、長い履歴の追跡）で Terra を選ぶのは、能力不足を補うためではなく、Sol とほぼ同等の長文脈リコールを Sol より安く買うためである。`luna` は長文脈リコールに崖があり（5.6 世代の計測: MRCR 41.3% / Sol 91.5% / Terra 89.6%、[OpenAI](https://openai.com/index/gpt-5-6)。gpt-6 世代は未計測）、effort 引き上げで緩和されるという実測は公表されていない。

昇格表で opencode 行と cursor 行の長文脈を対象外にしているのは、どちらも長文脈リコールが未計測だからである。
