---
name: drawio
description: Use when creating or editing draw.io diagrams such as architecture diagrams, flowcharts, sequence diagrams, or ER diagrams, especially when working with `.drawio` or `.drawio.xml` files.
---

# Draw.io Diagram Creation

## Overview

Start from a bundled template, not from empty XML. Always read `resources/references/xml-structure.md` before editing diagram XML, and open `resources/references/font-config.md` only when you need export-safe font behavior or font troubleshooting.

## When to Use

- draw.io / diagrams.net 用の XML を作りたい
- `.drawio` または `.drawio.xml` を直接編集したい
- AWS アーキテクチャ図を作りたい
- フローチャート、シーケンス図、ER 図を作りたい
- 日本語ラベル込みで崩れにくい図を出したい

使わない場面:

- 単なる画像編集だけをしたい
- SVG / HTML / Mermaid の方が自然な図を作りたい

## First Pass

1. 図の種類を `AWS` `flowchart` `sequence` `ER` から決める
2. 対応する template を選ぶ
3. `resources/references/xml-structure.md` を読む
4. 要素追加前に font と layout の必須ルールを確認する
5. XML 生成後に export 崩れ前提で検証する

## Template Routing

- AWS: `resources/assets/templates/aws-basic.drawio.xml`
- Flowchart: `resources/assets/templates/flowchart-basic.drawio.xml`
- Sequence: `resources/assets/templates/sequence-basic.drawio.xml`
- ER: `resources/assets/templates/er-basic.drawio.xml`

## Non-Negotiable Rules

- すべての text 要素に `fontFamily=Helvetica` を明示する
- `mxGraphModel` に `defaultFontFamily="Helvetica"` を入れる
- 矢印を先、ラベルと shape を後に置く
- `page="0"` を使い、背景は transparent に保つ
- 座標は 10px グリッドに寄せる
- 日本語ラベル幅は `文字数 x 35 + 10` を目安にする

## Output Checklist

- template をベースにしている
- text 要素ごとの `fontFamily` が欠けていない
- 矢印とラベルの間隔が 20px 以上ある
- 日本語ラベルが折り返していない
- export 後も font 崩れしない前提で書かれている

## Common Mistakes

- `defaultFontFamily` だけ設定して text 要素側を省略する
- shape を先に置いて connector が前面に出る
- 日本語ラベル幅を英語ラベルと同じ感覚で置く
- template を使わず空の XML から始める
- font 問題でもないのに `font-config.md` を先に掘りすぎる

## References

- `resources/references/xml-structure.md`
- `resources/references/font-config.md`
- `resources/assets/templates/`
