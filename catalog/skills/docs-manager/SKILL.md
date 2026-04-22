---
name: docs-manager
description: Use when reviewing, validating, or creating project documentation with metadata, tag, link, and size rules, especially in repositories that use `.docs-manager-config.json`.
---

# Docs Manager

## Overview

This skill is for documentation quality control, not generic prose editing. Start from project configuration, then validate metadata, tags, size, and links in that order.

The detailed schemas and examples already live in `templates/`, `examples/`, and `references/`.

## When to Use

- docs directory や `.md` 群の品質をレビューしたい
- metadata, tags, size limit, link validity を確認したい
- 新しいドキュメントを既存ルールに合わせて作りたい
- project-specific documentation rules を適用したい

使わない場面:

- 文章の言い回しだけ直したい
- 1ファイルの内容要約だけが目的
- docs rule より設計内容そのもののレビューが主目的

## First Pass

1. `.docs-manager-config.json` があるか確認する
2. `docs_root` と project type を確認する
3. metadata rule を確認する
4. tag / size / link rule を順に見る
5. project-specific rule があれば最後に適用する

## Validation Order

### 1. Configuration

- `.docs-manager-config.json` があるか
- なければ default behavior で見るか
- `docs_root` がどこか

### 2. Metadata

- date
- audience
- tags
- format が project rule に合っているか

### 3. Tag System

- required tag prefix が揃っているか
- separator が統一されているか
- vocabulary 違反がないか

### 4. Size

- 長すぎる document がないか
- split 候補があるか

### 5. Links

- internal path
- section anchor
- external URL
- image path

## Config Examples

設定例は既存ファイルを使う。

- template: `templates/docs-manager-config.template.json`
- examples:
  - `examples/generic-config.json`
  - `examples/dotfiles-config.json`
  - `examples/custom-project-config.json`

## Common Mistakes

- config を見ずに generic rule を押し付ける
- metadata だけ見て tag や size を飛ばす
- project-specific rule を本文ルールと混ぜる
- link validation を後回しにして壊れた参照を残す
- prose quality review と documentation governance を混同する

## Resources

- Template: `templates/docs-manager-config.template.json`
- Metadata reference: `references/metadata-standards.md`
- Tag reference: `references/tag-systems.md`
- Size reference: `references/size-management.md`
- Config patterns: `references/config-templates.md`
