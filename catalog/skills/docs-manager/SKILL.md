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

最初に effective rules を短く確定してから作業する。最低限、`docs_root`、`project_type`、metadata fields、required tags、tag separator、size limits、link validation の有効/無効を明示する。

config がない場合は default behavior として扱う:

- `docs_root`: `./docs`
- `project_type`: `generic`
- metadata fields: `最終更新`, `対象`, `タグ`
- date format: `YYYY-MM-DD`
- required tags: `category/`, `audience/`
- tag separator: `, `
- size limits: ideal 300 lines, acceptable 500 lines, warning 1000 lines, maximum 2000 lines
- link validation: enabled unless the project clearly disables it

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
- tag vocabulary は tag 値だけに適用し、`対象` / `Audience` field の表記には適用しない。ただし config が audience field の語彙制限を明示している場合は従う
- vocabulary が明示されていない場合は、required prefix と separator の検証に限定する

### 4. Size

- 長すぎる document がないか
- split 候補があるか
- size limits は line count として扱う
- `acceptable` 超えは改善候補、`warning` 超えは warning、`maximum` 超えは split 必須として扱う

### 5. Links

- internal path
- section anchor
- external URL
- image path
- link validation が disabled の場合は実行も要求もしない
- section anchor は markdown heading から解決する。入力や実ファイル確認で anchor がないと分かっている場合は、追加推測せず missing anchor として扱う

### 6. Project-Specific Rules

- `custom_rules.required_files` の不足
- `custom_rules.update_frequency` の対象と stale 判定
- required file が存在しない場合、その file の update frequency は applicable but unverifiable として、stale 判定を試みず missing file を先に直す問題として扱う

## Creating Documents

新しい document を作るときも validation と同じ rules を使う。

1. effective rules を確定する
2. `docs_root` 配下の要求された path に作る
3. title と metadata block を入れる
4. required tags をすべて入れる
5. 既存ファイルへの link は存在確認できる path / anchor だけを使う
6. concise な runbook / reference / guide shape に収め、project-specific 情報がない場合は断定しない
7. 作成後に metadata / tags / size / links の検証結果を添える

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
