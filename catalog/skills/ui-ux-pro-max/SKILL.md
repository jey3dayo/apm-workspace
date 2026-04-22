---
name: ui-ux-pro-max
description: Use when designing, reviewing, or improving UI/UX for web or mobile products, especially when the task involves layout, hierarchy, style direction, interaction quality, accessibility, or stack-specific interface decisions.
---

# UI UX Pro Max

## Overview

This skill is for interface decisions, not backend or generic product strategy. Start by deciding what kind of UI task this is, then pull only the relevant domain or stack guidance instead of scanning the full dataset.

The heavy reference data already lives in `data/` and the search entry point is `scripts/search.py`.

## When to Use

- 新しい画面や UI コンポーネントを設計したい
- 既存 UI の見た目、使いやすさ、情報階層を改善したい
- 色、タイポグラフィ、余白、モーション、ナビゲーションを決めたい
- stack ごとの UI 方針を取りたい
- UI レビューで「何が悪いか」を言語化したい

使わない場面:

- backend や API 設計だけの相談
- UI と無関係なパフォーマンス調整
- インフラや運用自動化
- 一般的な PM 戦略だけの相談

## First Pass

最初に次の 3 つを決める。

1. task type:
   - design
   - review
   - implementation guidance
2. primary domain:
   - `ux`
   - `style`
   - `color`
   - `typography`
   - `chart`
   - `product`
3. stack:
   - react / nextjs / vue / svelte / astro / swiftui / react-native / flutter / html-tailwind / shadcn など

## Default Review Order

1. accessibility
2. interaction and touch targets
3. layout and responsive behavior
4. typography and color
5. motion and feedback
6. stack-specific implementation details

UI が崩れていても、まず配色や style から入らず、操作性と hierarchy を先に見る。

## Search the Dataset

必要な時だけ `scripts/search.py` で該当データを引く。

```bash
python /Users/t00114/.apm/catalog/skills/ui-ux-pro-max/scripts/search.py "pricing page hierarchy" --domain ux
python /Users/t00114/.apm/catalog/skills/ui-ux-pro-max/scripts/search.py "dashboard cards" --domain style
python /Users/t00114/.apm/catalog/skills/ui-ux-pro-max/scripts/search.py "form patterns" --stack react
python /Users/t00114/.apm/catalog/skills/ui-ux-pro-max/scripts/search.py "admin panel" --design-system -p "My Product"
```

`--domain` は観点別、`--stack` は技術別、`--design-system` は方針の素案作成に使う。

## Domain Guide

- `ux`:
  - accessibility, interaction, layout, forms, navigation
- `style`:
  - visual direction, component personality, product fit
- `color`:
  - palette, semantic tokens, contrast
- `typography`:
  - font pairing, scale, readability
- `chart`:
  - chart type selection, labeling, color usage
- `product`:
  - product type ごとの相性やトーン

## Stack Guide

stack guidance is for implementation constraints, not for deciding whether the UI idea is good. First decide the interaction pattern, then check the stack-specific file only if the implementation details matter.

## Common Mistakes

- 巨大なルール一覧を最初から全部読む
- aesthetics を accessibility より先に見る
- stack 制約を UX 判断の代わりに使う
- 一般論で済む相談なのに design-system 生成まで走る
- UI 問題を backend や state logic の問題と混ぜる

## Resources

- Search entry point: `scripts/search.py`
- Domain data: `data/*.csv`
- Stack data: `data/stacks/*.csv`
