---
name: slide-docs
description: Use when reviewing or creating Markdown-based presentation slides such as Marp, Deckset, reveal.js, or `.slides.md` decks. Do not use for general document summarization or non-presentation prose review.
---

# Slide Docs

## Overview

This skill is for presentation decks, not generic documents. First decide whether the user needs slide review, slide creation, or tool-specific syntax help. Only pull in syntax references when the deck framework actually matters.

## When to Use

- Marp / Deckset / reveal.js / `.slides.md` をレビューしたい
- スライドの構成、メッセージ、見た目を改善したい
- 新しい発表資料のアウトラインや本文を作りたい
- tool-specific syntax や機能差分を確認したい

使わない場面:

- 一般文書の要約や校正だけをしたい
- プレゼンとは無関係な Markdown 文書を見たい
- syntax 確認の必要がない一般論だけの相談

## First Decision

最初に次のどれかを決める。

1. レビュー
2. 作成支援
3. ツール固有構文の確認

この切り分けをしないまま評価尺度や構文詳細に入らない。

## Review Workflow

1. deck の目的と対象 audience を確認する
2. 全体の流れを見て、1スライド1メッセージになっているか確認する
3. タイトル、本文、図表、コードの読みやすさを確認する
4. 結論と call-to-action が明確か確認する

## Creation Workflow

1. 発表目的と audience を確認する
2. 3つ前後の主要メッセージに絞る
3. スライド順を決めてから本文を書く
4. 図表や speaker notes が必要か決める

## Review Criteria

### 1. Structure

- 導入 -> 本論 -> 結論の流れがあるか
- 話のジャンプが大きすぎないか
- スライド数が時間に対して多すぎないか

### 2. Messaging

- 各スライドの主張が1つに絞れているか
- text が多すぎないか
- 聴衆が覚えるべき点が見えるか

### 3. Visuals

- タイトルと本文の hierarchy があるか
- 図、画像、コードが読みやすいか
- 配色や余白が一貫しているか

### 4. Delivery

- 発表者ノートが必要か
- デモ、Q&A、次のアクションが整理されているか

## Context7

Context7 は Marp / Deckset / reveal.js の構文や機能確認が必要なときだけ使う。レビューや構成改善だけなら、まず本文と流れを見る。

## Common Mistakes

- 一般文書レビューと同じ感覚で長文化する
- 構成確認より先に配色やアニメーションをいじる
- syntax 確認が不要なのに Context7 へ飛ぶ
- レビューと作成支援の出力形式を混ぜる
