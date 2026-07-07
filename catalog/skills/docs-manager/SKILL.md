---
name: docs-manager
description: Use when reviewing, validating, creating, updating, or fixing project documentation, especially docs directories and Markdown files governed by metadata, OKF / YAML frontmatter, tag, link, and size rules such as `.docs-manager-config.json`. Also use when a user asks to make docs OKF-compatible or says to use OKF docs, even if they do not spell out the frontmatter fields.
---

# Docs Manager

## Overview

This skill is for project documentation maintenance, not generic prose editing. Start from project configuration, then review, create, update, fix, or validate documentation against metadata, OKF compatibility, tags, size, and links in that order.

The detailed schemas and examples already live in `templates/`, `examples/`, and `references/`.

Out of scope: 文章の言い回しだけの修正、1ファイルの内容要約、docs rule より設計内容そのもののレビューが主目的の作業。

## First Pass

1. `.docs-manager-config.json` があるか確認する
2. `docs_root` と project type を確認する
3. metadata profile と metadata rule を確認する
4. tag / size / link rule を順に見る
5. project-specific rule があれば最後に適用する

最初に effective rules を短く確定してから作業する。最低限、`docs_root`、`project_type`、metadata profile、metadata fields、required tags、tag separator、size limits、link validation の有効/無効を明示する。

config がない場合は default behavior として扱う:

- `docs_root`: `./docs`
- `project_type`: `generic`
- `metadata_profile`: `legacy`
- metadata fields: `最終更新`, `対象`, `タグ`
- date format: `YYYY-MM-DD`
- required tags: `category/`, `audience/`
- tag separator: `, `
- size limits: ideal 300 lines, acceptable 500 lines, warning 1000 lines, maximum 2000 lines
- link validation: enabled unless the project clearly disables it

ただし、ユーザーが OKF / Open Knowledge Format / YAML frontmatter 対応を求めた場合は、config がなくても `metadata_profile: okf` 相当として扱う。`type` を required、`title`, `description`, `resource`, `tags`, `timestamp`, `audience`, `owner` を recommended とし、既存 docs への最小 frontmatter 追加を第一候補にする。OKF 化のためだけに本文を大きく再構成したり、新規説明 docs を増やしたりしない。

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

`metadata_profile` が `okf` の場合:

- YAML frontmatter を canonical metadata として扱う
- `type` を required field として見る
- `title`, `description`, `resource`, `tags`, `timestamp`, `audience`, `owner` を recommended fields として見る
- `timestamp` は `最終更新` / date field の canonical alias として扱う
- `tags` は `タグ` / tags field の canonical alias として扱う
- 既存の body metadata block がある場合は legacy alias として許容し、frontmatter と矛盾する場合だけ warning にする
- OKF field 以外の project governance、size limits、required tag prefixes、link validation は `.docs-manager-config.json` 側の rule を優先する

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
- external URL は redirect 先も確認する。厳格な validator で落ちそうな 301/302 がある場合は、本文意図を変えずに canonical URL へ寄せる

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

## Updating or Fixing Documents

既存 document を更新・修復するときは、先に実態との差分と対象読者を確認する。

1. 変更元を確認する: `git diff`、実装ファイル、設定、運用手順、ユーザー指定のどれが根拠かを明示する
2. 既存 document の該当 section を探し、新しい重複 section を作らず in-place で直す
3. stale な記述、壊れた link、不足 metadata、tag/size 違反を分けて扱う
4. 手動で書かれた判断や project-specific な文体を保ち、汎用テンプレートで上書きしない
5. 大きな再構成が必要な場合は、編集前に affected files と最小変更案を提示する
6. 更新後に metadata / tags / size / links の確認結果を添える

OKF 対応として既存 docs を直す場合:

1. まず既存 Markdown の本文を保ち、YAML frontmatter を追加または修正する
2. config がない repo でも、OKF 指定があれば frontmatter を canonical metadata として扱う
3. `tags` には project rule の required prefix を満たす値を入れる
4. 既存の dirty diff がある場合は、OKF metadata hunk と本文 hunk を分けて扱う。stage / review / commit では OKF hunk だけを混ぜずに確認する
5. 調査メモや一時 report は repo guidance が指定する一時ディレクトリに置く。指定がなければ repo root を汚さず、必要最小限にする

## Common Mistakes

- config を見ずに generic rule を押し付ける
- metadata だけ見て tag や size を飛ばす
- project-specific rule を本文ルールと混ぜる
- link validation を後回しにして壊れた参照を残す
- prose quality review と documentation governance を混同する

## Resources

- Config template: `templates/docs-manager-config.template.json`
- Config examples: `examples/generic-config.json`, `examples/dotfiles-config.json`, `examples/custom-project-config.json`, `examples/okf-config.json`
- Metadata reference: `references/metadata-standards.md`
- Tag reference: `references/tag-systems.md`
- Size reference: `references/size-management.md`
- Config patterns: `references/config-templates.md`
