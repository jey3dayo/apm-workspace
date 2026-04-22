---
name: typescript
description: Use when reviewing or improving TypeScript code or configuration, especially for strict mode, `any` removal, type assertions, narrowing, or tsconfig-based diagnosis.
---

# TypeScript Project Review

## Overview

Start from compiler settings, then move to `any`, assertions, and narrowing. This skill is for project-specific review and repair decisions, not for re-explaining the TypeScript handbook.

Use `references/type-safety-patterns.md` when you need concrete replacement patterns after finding an unsafe area.

## When to Use

- TypeScript の型安全性をレビューしたい
- `any` や unsafe assertion を減らしたい
- `tsconfig.json` の strictness を見直したい
- 型エラーの原因が設計か narrow 不足かを切り分けたい
- TypeScript 前提の review 基準をそろえたい

使わない場面:

- JavaScript 一般論だけで足りる
- 特定ライブラリの API 仕様だけを調べたい

## First Pass

1. `tsconfig.json` で strict 系オプションを確認する
2. `any` と type assertion を横断で洗う
3. `unknown` からの narrowing と user-defined guards を確認する
4. エラー処理が型で表現されているかを見る
5. 型の重複や surface 設計の崩れを最後に見る

## Review Areas

### 1. Compiler Configuration

- `strict` 系が有効か
- lint と compiler のルールが矛盾していないか
- type-only import や build 設定に無駄がないか

### 2. Unsafe Types

- `any` が本当に必要か
- assertion で問題を隠していないか
- `unknown` と narrow で代替できないか

### 3. Type Surfaces

- interface / type alias の責務が明確か
- generic 制約が緩すぎないか
- union が discriminated になっているか

### 4. Error Handling

- 失敗状態が型に出ているか
- optional / nullable の扱いが曖昧でないか
- guard なしで危険なプロパティアクセスをしていないか

## Rules Of Thumb

- `any` は導入より削除を優先する
- assertion は「証明済み」箇所に閉じ込める
- `unknown` を受けて narrow する流れを基本にする
- `Result` 風パターンや判別可能 union で失敗を表現する

## Common Mistakes

- `strict` 未確認のまま individual error だけ潰す
- assertion でコンパイラを黙らせて review を通す
- `any` を境界だけでなく内部ロジックまで広げる
- runtime validation が必要な入力を型だけで信じる

## References

- `references/type-safety-patterns.md`
