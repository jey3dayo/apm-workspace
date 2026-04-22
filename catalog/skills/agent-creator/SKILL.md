---
name: agent-creator
description: Use when creating a new subagent, refactoring an existing agent definition, or deciding tool access and role boundaries for agent-based workflows.
---

# Agent Creator

## Overview

This skill is for designing agent definitions, not for executing the agent's task itself. Start by clarifying the agent's single responsibility, then decide tool access, then draft from the template.

Use the bundled template, checklist, and detailed reference instead of rewriting the full structure from memory.

## When to Use

- 新しい subagent を作りたい
- 既存 agent の role や tools を整理したい
- agent の責務分離や境界を見直したい
- orchestrator / validator / utility など、どの設計に寄せるか迷っている

使わない場面:

- 単に task prompt を1回だけ書きたい
- skill や command を作るべきで、agent 化がまだ妥当か分からない
- agent 定義ではなく、既存 agent の実行結果レビューだけをしたい

## First Pass

1. その agent の責務を 1 文で言う
2. 何をしない agent かも決める
3. 必要な tools を最小で決める
4. agent type を既存パターンから選ぶ
5. template から下書きを作る
6. checklist で抜けを潰す

## Core Decisions

### 1. Responsibility

- 1 agent = 1 concentrated responsibility
- 役割が広すぎるなら分割を優先する
- 実行役か、検証役か、調整役かを先に決める

### 2. Tool Access

- `tools: ["*"]`:
  - 探索や横断分析が必要な agent
  - orchestrator や domain expert 向け
- 明示的な tool list:
  - 単機能で高速に回したい agent
  - utility / validator 向け
- `inherit`:
  - 親の tool 境界を維持したいときだけ使う
  - 前提が複雑になるので、理由が薄ければ避ける

### 3. Agent Shape

- domain expert:
  - 特定領域の深い判断を担う
- project-specific:
  - プロジェクト固有ルールを適用する
- utility:
  - 単機能で決定的な処理を行う
- orchestrator:
  - 複数 agent を束ねる
- autonomous:
  - 探索や反復改善を主に行う

詳細は `references/agent-details.md` を参照する。

## Drafting Workflow

1. `resources/templates/agent-template.md` を土台にする
2. frontmatter の `name` / `description` / `tools` を先に固める
3. `Role` と `Activation Context` を先に書く
4. `Capabilities` と `Output Format` を最小限に絞る
5. `resources/checklist.md` で構造・統合・出力品質を確認する

## Frontmatter Rules

- `name`:
  - filename と一致させる
  - kebab-case にする
- `description`:
  - `Use when ...` で始める
  - 何をするかではなく、いつ使うかを書く
- `tools`:
  - 必要最小限から始める
- `color`:
  - 役割の種別に合わせる
- `model`:
  - 通常は軽いモデルから始め、複雑 reasoning が必要な時だけ上げる

## Common Mistakes

- 役割が広すぎて、結局なんでも屋になる
- `tools: ["*"]` を理由なく配る
- `description` に workflow を書きすぎる
- template をそのまま残して、実際の activation 条件を書かない
- parent command や related agents を空欄のままにする

## Resources

- Template: `resources/templates/agent-template.md`
- Checklist: `resources/checklist.md`
- Detailed patterns: `references/agent-details.md`
- Examples:
  - `resources/examples/domain-expert-agent.md`
  - `resources/examples/project-specific-agent.md`
  - `resources/examples/validator-agent.md`
