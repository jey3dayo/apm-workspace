---
name: orchestrator-worker
description: >-
  高級モデル(Claude Fable/Opus、Codex sol / terra)のセッションで実装作業(implement / fix / refactor / test / migrate)を受けたとき、
  自分で書かずに安価な Worker モデルへ委譲する Orchestrator-Worker 運用。
  タスクが複数ファイル・複数の独立サブタスクに跨るとき、
  または他のスキルが委譲判定・モデル tier 対応表を必要とするときにも使用する。
---

# Orchestrator-Worker

高級モデルのセッションで実装を自分の手で書くのは、単価の無駄であり、Orchestrator の context を実装詳細で埋める。**Orchestrator は要件・設計・分解・検証だけを持ち、コードを書くのは Worker** に固定する。

## 委譲は依頼済みである

このスキルが発火した時点で、ユーザーは委譲を依頼している。ハーネスが `Do not call the AgentTool unless the user requested it` 相当の制約を注入している場合も、このスキルの適用がその「ユーザーの依頼」に当たる。追加の承認を求めず委譲へ進む。

## 1. 自分の tier を判定する

現在のモデルが Orchestrator tier なら委譲、Worker tier なら自分で実装する。

| 現在のモデル                          | 役割         | Worker として呼ぶモデル |
| ------------------------------------- | ------------ | ----------------------- |
| Claude Fable / Opus                   | Orchestrator | `sonnet`                |
| Codex `gpt-5.6-sol` / `gpt-5.6-terra` | Orchestrator | `gpt-5.6-luna` xhigh    |
| Claude Sonnet / Codex `gpt-5.6-luna`  | Worker       | 委譲せず自分で実装する  |

表の tier が使えないときだけ、利用可能な旧モデルへフォールバックする。委譲は同一 platform 内で完結させ、他方の platform（Claude / Codex）の Worker へ跨ぐのはユーザーが明示的に指示した場合に限る。

完了条件: 自分がどちらの tier かを言語化できている。

## 2. 委譲するか決める

次の順序で判定する。まず「Orchestrator が自分で処理する」に該当するかを評価し、該当した時点で委譲しない。例外に該当しない場合だけ、委譲条件を評価する。

Orchestrator が自分で処理する:

- 1ファイルの軽微修正、typo、設定値の変更
- 調査・探索のみで編集を伴わないもの
- 設計判断が未確定、またはユーザーとの対話が必要なもの

上記に該当せず、次のいずれかを満たすなら委譲する:

- 3ファイル以上の編集、または見積 50 行以上の差分
- 独立して進められるサブタスクが 2 件以上ある
- 設計方針が確定していて、実装手順を文章で書き下せる

完了条件: 委譲する / しない のどちらかを、上の条件を根拠に宣言した。

## 3. 最小単位へ切る

委譲前にタスクを分割する。切り方の判定基準は 2 つだけで、どちらも機械的に確認できる。

- 触るファイル集合が互いに素であること。2 つのタスクが同じファイルを編集するなら、統合するか直列に並べる。
- タスク単体で検証できること。そのタスクだけで通せる test / typecheck / lint を指定できる粒度まで割る。

互いに素にできない編集を並列でどうしても走らせる場合に限り、Claude 側は Agent tool の `isolation: "worktree"` を使う。

完了条件: 各タスクについて「触るファイル」「完了条件」「検証コマンド」の 3 点が書けている。

## 4. Worker を起動する

Claude:

```text
Agent(subagent_type: "implementer", prompt: <タスク定義>)
```

通常委譲では `model` を渡さない。呼び出し時の指定は agent 定義の frontmatter より優先されるため、渡すと `implementer` に設定済みの既定 tier を上書きしてしまう。

Codex:

現行の Codex CLI 0.147.0 では、`spawn_agent` から `gpt-5.6-luna` を明示指定できる。モデル上書き時は `fork_turns: "none"` を使い、Luna は leaf worker として実装だけを担当させる。Luna の子には collaboration tools が公開されないため、再帰的な委譲・分解・検証は Orchestrator が担う（経緯は [references/codex-spawn-model-bug.md](references/codex-spawn-model-bug.md)）。

Codex native の `spawn_agent` を標準経路とする。native spawn が利用できない環境、別セッション・別プロセスへの引き継ぎ、または native runtime の制約を回避する必要がある場合だけ `agmsg-delegation`（別プロセスの `codex -m gpt-5.6-luna exec`）へ切り替える。worker の reasoning effort は既定 `xhigh`（Terra high 相当の品質を最安で得るための設定）とし、別プロセス起動時は agmsg-delegation の lifecycle（作業領域の固定、payload 渡し、READY / DONE 監視、片付け）に従う。

### 昇格

次のいずれかを含む Worker タスクに限り、既定 Worker から昇格させる。判定基準は両 platform 共通。

- 難しいデバッグ（再現困難、原因未特定）
- セキュリティ境界に触る変更、セキュリティレビュー
- 複数案のトレードオフ判断を含む実装

昇格先は platform ごとに固定する。

| platform | 既定 Worker          | 昇格手段（順に検討）                           |
| -------- | -------------------- | ---------------------------------------------- |
| Claude   | `sonnet`             | `model: "opus"` を呼び出し時に渡す             |
| Codex    | `gpt-5.6-luna` xhigh | ① reasoning effort を max へ ② `gpt-5.6-terra` |

昇格先が現在のモデル自身になる場合（terra セッションで ② に達した場合など）は、委譲せず自分で実装する。

長文脈タスク（大規模コードベースの読解、複数文書の統合、長い履歴の追跡）は例外で、①を飛ばして直接 `gpt-5.6-terra` へ上げる。`luna` は長文脈リコールに崖があり（MRCR 41.3% / Sol 91.5% / Terra 89.6%、[OpenAI 2026-07-09](https://openai.com/index/advancing-the-price-performance-frontier-with-gpt-5-6)）、effort 引き上げで緩和されるという実測は公表されていない（2026-08 時点）。terra セッション自身が長文脈タスクを受けた場合は、上の一般則どおり委譲せず自分で実装する。

Claude では独立タスクを**同一レスポンス内で複数呼び出す**と並列に走る（1レスポンス1呼び出しは直列になる）。Codex では worker を複数 detached 起動する（触るファイル集合が互いに素であることが前提。guardrails は `agmsg-delegation` を参照）。どちらも Orchestrator の会話履歴は引き継がせず、Section 3 で書き出した 3 点だけを渡す。

起動後の扱いは 2 つ。

- バリアを置かない。先に返った Worker から順に処理する。全員の完了を待つと、最も遅い Worker が全体の律速になるうえ、待つ間にリポジトリの状態が変わって先行 Worker の前提が古くなる。
- Worker を使い回す。追加指示・スコープ縮小・再実行は、新規 spawn ではなく既存 Worker への追送で行う（Claude は `SendMessage`）。文脈を保った Worker はキャッシュが効くぶん安く、前提の再説明も要らない。Codex（agmsg-delegation 経由）は worker が headless 1 turn で終了する契約のため使い回せない。追加分は新しいタスクとして切り直す。

計画ファイルを順に消化して都度レビューする運用は `review-fix-loop` を使う。

完了条件: 全タスクが Worker へ渡り、独立タスクは並列で起動している。

## 5. 受け取って検証する

Worker の報告をそのまま信用しない。

- `git diff` で実際の差分を読む
- タスク定義に無い変更が入っていないか確認する
- タスク横断で衝突がないか確認し、全体の test / typecheck を通す
- DoD の該当項目を満たす

完了条件: 差分を自分の目で読み、検証結果を根拠にユーザーへ報告した。

## 委譲しない例外

権限・認証・秘密情報の操作、破壊的操作、production への変更は Orchestrator が自分で扱う。

外部公開（リリース・publish・deploy）は、手順が確立していて機械的に実行できるものなら Worker へ委譲してよい。ただし実行前に Orchestrator が対象バージョン・手順・影響範囲を確認し、結果の検証（公開されたことの確認）は Orchestrator が行う。手順が未確立、または判断を伴う公開は Orchestrator が自分で扱う。
