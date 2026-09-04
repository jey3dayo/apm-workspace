---
name: todo-changelog-ops
description: "Use when adding, closing, or pruning entries in a repository's `TODO.md`, when moving finished work into `CHANGELOG.md` (including work tracked in `todo.txt`, GitHub Issues, or PRs), when setting up local task tracking for a repository that has no tracker, or when deciding where a task belongs among `todo.txt`, GitHub Issues, docs, and `TODO.md` (置き場の振り分け). Do not use for entrypoint-docs drift review (`docs-review`), for cutting a release version section or tag (the repository's release workflow), for manager-facing work reports (`work-log-maintenance`), or for commit splitting (`atomic-commit`)."
---

# TODO / CHANGELOG Ops

外部トラッカーを使わず、リポジトリ内の 2 ファイルだけで作業を追跡するローカル標準。`TODO.md` が未完了、`CHANGELOG.md` が完了済みを持つ。ツールは要らない。

## 置き場の振り分け

リポジトリが `todo.txt`（tuxedo 運用）や GitHub Issues を併用している場合は、この 2 ファイル標準へ寄せる前に次の基準で振り分ける。

1. 完了したら消えていい軽い単発タスク → `todo.txt`（`tuxedo` スキル）
2. 経緯・判断理由・議論を後から辿りたいもの → GitHub Issues（`note:<issue URL>` で todo.txt から参照してよい）
3. 完了という概念がなく恒常的に参照するルール・手順 → `docs/` / `AGENTS.md` 系
4. 上記のどれも使っていないリポジトリ → この標準（`TODO.md` + `CHANGELOG.md`）

todo.txt のタスクが設計判断を要するほど育ったら issue へ昇格し、todo.txt 側は issue リンクを残して閉じるか行ごと消して一本化する。

## 書式

書式そのものは標準化しない。リポジトリごとに散文量も優先度記号も違ってよく、**必須項目が読み取れることだけ**を要求する。既存ファイルがあるときは、そこの現物書式に合わせる。

## TODO エントリの必須項目

| 項目   | 意味                                                                                             |
| ------ | ------------------------------------------------------------------------------------------------ |
| 優先度 | リポジトリ定義の記号。運用していないリポジトリでは省いてよい                                     |
| 対象   | write scope。触るファイル・ディレクトリ・リソース                                                |
| 検証   | どうなったら完了か。code audit / focused test / manual verification / CI gate のどれで判定するか |
| 起票日 | `YYYY-MM-DD`                                                                                     |

判断理由や計測結果が本体になる項目は散文で残す。要約すると次に読む人が調べ直すことになる。

検証手段が無い懸念は起票しない。既存項目と重なるものは新規追加せず、該当項目の検証条件へ統合する。

## CHANGELOG の 2 モード

リリースを切るかどうかで決まる。1 リポジトリ 1 モード。

- versioned — リリース成果物とバージョンがあるリポジトリ。[Keep a Changelog](https://keepachangelog.com/) 形式。完了分は `## [Unreleased]` 配下へ入れ、`### Features` / `### Bug Fixes` / `### Documentation` / `### Maintenance` へ分類する。バージョン節への切り出しはリリース手順の担当。
- dated — 継続デプロイでバージョンを持たないリポジトリ。`## YYYY-MM-DD — 一行要約` を新しい順に積む。日付見出しは版の代わりであって手抜きではない。

どちらも本文は日本語・過去形で、利用者や運用者から見た結果を書く。実装手段やファイル名を主語にしない。

## 追加する

1. 既存項目へ統合できないことを確認する。
2. 該当セクションへ必須項目を満たす形で追加する。セクションが無いときだけ新設する。
3. 起票日を書く。

## 完了して CHANGELOG へ移す

タスクがどこで管理されていても（`todo.txt` / `TODO.md` / GitHub Issue / PR）、実装が landed したら CHANGELOG へ 1 エントリ書く。着手中や検証待ちの項目は元の置き場に残す。

1. 元の置き場を閉じる。`TODO.md` は該当エントリを削除（親項目へ寄せる場合は、残す検証観点を親側へ移してから消す）、`todo.txt` は `done` → `archive`、issue はクローズ。PR は merge 自体が完了。
2. CHANGELOG のモードに従って 1 エントリ追加する。issue / PR 起点のエントリには番号（`#12`）を添えて経緯を辿れるようにする。
3. 利用者に見えない内部変更だけの項目は CHANGELOG へ書かず閉じるだけにし、理由をコミットメッセージに残す。

## 棚卸し

起票日からの経過は review pressure であって自動降格ではない。古い項目は着手・分割・理由付きの降格のいずれかを選ぶ。据え置くときは最終レビュー日と理由を書き足す。

`TODO.md` が肥大化したら、優先度を下げる前に「これは恒久ルールではないか」を確認する。ルールなら `CLAUDE.md` や `.claude/rules/` などリポジトリのルール置き場へ移し、TODO からは消す。

## リポジトリ固有の拡張

パーサ、export スクリプト、優先度 taxonomy、shard 計画を持つリポジトリでは、それらが正本になる。作業前に `CLAUDE.md` と `.claude/rules/`、`TODO.md` 冒頭の運用メモを確認し、この標準と食い違う場合はリポジトリ側に従う。
