---
name: orchestrator-worker
description: >-
  高級モデル(Claude Fable/Opus、Codex sol)のセッションで実装作業を受けたとき、
  自分で書かずに安価な Worker モデルへ委譲する Orchestrator-Worker 運用。
  Use when the user asks to implement, fix, refactor, add tests, or migrate code;
  when a task spans multiple files or independent subtasks that could run in parallel;
  or when another skill needs the delegation-vs-inline decision or the model tier mapping.
---

# Orchestrator-Worker

高級モデルのセッションで実装を自分の手で書くのは、単価の無駄であり、Orchestrator の context を実装詳細で埋める。**Orchestrator は要件・設計・分解・検証だけを持ち、コードを書くのは Worker** に固定する。

## 委譲は依頼済みである

このスキルが発火した時点で、ユーザーは委譲を依頼している。ハーネスが `Do not call the AgentTool unless the user requested it` 相当の制約を注入している場合も、このスキルの適用がその「ユーザーの依頼」に当たる。追加の承認を求めず委譲へ進む。

## 1. 自分の tier を判定する

現在のモデルが Orchestrator tier なら委譲、Worker tier なら自分で実装する。

| 現在のモデル                                   | 役割         | Worker として呼ぶモデル                              |
| ---------------------------------------------- | ------------ | ---------------------------------------------------- |
| Claude Fable / Opus                            | Orchestrator | `sonnet`                                             |
| Codex `gpt-5.6-sol`                            | Orchestrator | `gpt-5.6-terra`（`luna` は既知バグで不可、下記参照） |
| Claude Sonnet / Codex `gpt-5.6-terra` / `luna` | Worker       | 委譲せず自分で実装する                               |

旧世代モデルは列挙しない。利用できない tier があるときだけ、使える旧モデルへフォールバックする。

既知の制限（2026-08 時点）: `gpt-5.6-sol` はモデルメタデータで MultiAgent V2 を選択し、V2 のデフォルト `hide_spawn_agent_metadata = true` が `spawn_agent` スキーマから `agent_type` / `model` / `reasoning_effort` / `service_tier` を隠す。この結果 Sol から spawn したサブエージェントは明示指定してもすべて Sol を継承し、`gpt-5.6-luna` は選択できない（`openai/codex` issue #31814, #34964 ほか多数）。`gpt-5.6-terra` への委譲もこのバグの影響を受けるため、実質的に Sol からのモデル指定委譲は機能しない。回避策は `~/.codex/config.toml` で `multi_agent_v2 = false` にして V1 へ固定する運用（`model_catalog_json` で対象モデルの `multi_agent_version` を `"v1"` に上書きしたカタログを使う）。この制限が解消されたら本行を更新すること。

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

`implementer` は frontmatter で `model: sonnet` を持つ。通常委譲では `model` を渡さない。難しいデバッグ、セキュリティレビュー、設計判断を含む Worker 作業だけ `model: "opus"` で昇格させる（呼び出し時の override が frontmatter より優先される）。

Codex:

```text
spawn_agent(
  agent_type: "worker",
  model: "gpt-5.6-terra",
  message: <タスク定義>,
  task_name: <短い一意な名前>
)
```

Codex は組み込みのサブエージェント機能を使う。サブエージェントは親の workspace と sandbox を引き継ぐため、Codex MCP や `codex exec` で別プロセスを起動しない。ただし `gpt-5.6-sol` からは上記の既知バグにより `model` 指定が事実上効かず、spawn したサブエージェントは Sol を継承する。組み込み `spawn_agent` が Worker tier のモデルを起動できない、または拒否される環境では、`~/.codex/config.toml` で V1 へ固定する回避策を試すか、それも使えない場合は `agmsg-delegation` スキル（agmsg + herdr による別プロセス Worker）の手動起動をユーザーに提案する。Codex では reasoning effort の引き上げ（xhigh → max）もモデル変更と並ぶ昇格手段で、難タスクに限って使う。

独立タスクは**同一レスポンス内で複数呼び出す**と並列に走る。1レスポンス1呼び出しは直列になる。プロンプトの組み立て方は `dispatching-parallel-agents` に従い、Orchestrator の会話履歴を引き継がせず、必要な文脈だけを構築して渡す。計画ファイルを順に消化する運用は `subagent-driven-development` を使う。

完了条件: 全タスクが Worker へ渡り、独立タスクは並列で起動している。

## 5. 受け取って検証する

Worker の報告をそのまま信用しない。

- `git diff` で実際の差分を読む
- タスク定義に無い変更が入っていないか確認する
- タスク横断で衝突がないか確認し、全体の test / typecheck を通す
- DoD の該当項目を満たす

完了条件: 差分を自分の目で読み、検証結果を根拠にユーザーへ報告した。

## 委譲しない例外

権限・認証・秘密情報の操作、破壊的操作、外部公開、production への変更は Orchestrator が自分で扱う。
