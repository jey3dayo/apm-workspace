---
name: cccc
description: Use when measuring function-level Cognitive or Cyclomatic Complexity（複雑度）with `cccc` (moznion/cccc), triaging its ranking, or deciding whether to adopt it as a report or a CI/lefthook gate. Duplicate detection is `similarity`.
---

# cccc

`cccc` で関数ごとの Cognitive Complexity（SonarSource 方式）と Cyclomatic Complexity を測り、複雑な関数を triage する。1 バイナリで拡張子ごとにパーサを振り分けるので、TS と Rust の混在ツリーも 1 回で測れる。以下の挙動は v1.8.0 で実測した。

## 実行

1. バイナリが無ければ `mise x github:moznion/cccc@1.8.0 -- cccc ...` で一時実行する（以降の `cccc` もこの形に置き換える）。完全な版指定は mise の `minimum_release_age` に掛からない
2. 出力は `tmp/cccc/` に置き、まず除外なしで全体を見る。`cccc.toml` は cwd から親方向に自動で読まれ、その `exclude` が知らないうちに効くので、基準の実行には `--no-config` を付ける。

   ```bash
   mkdir -p tmp/cccc
   cccc --no-config <roots...> > tmp/cccc/all.json
   jq '.summary | {parse_error_count, parse_error_files}' tmp/cccc/all.json
   ```

   git 管理下では `.gitignore` を尊重するので、ignore 済みの `dist` / `target` / `node_modules` は入らない。JSON 出力は解析エラーがあっても警告を出さず exit 0 で終わるため、`parse_error_count` が 0 でなければ、その件数と `parse_error_files` を先に報告する

3. ノイズを `--exclude` で外して取り直す。よく外すのは、テスト、stories、dev 用モック、vendored UI（shadcn など）である。**glob は渡した走査ルートからの相対で照合される**。`cccc src` に `--exclude 'src/dev/**'` を渡すと、警告なしに何も除外しない。glob は `**/` で始める。

   ```bash
   cccc --no-config --exclude '**/__tests__/**' --exclude '**/*.{test,spec}.{ts,tsx}' \
     --exclude '**/*.stories.tsx' --exclude '**/tests/**' --exclude '**/tests.rs' \
     <roots...> > tmp/cccc/excl.json
   ```

   完了条件: 除外したかった各 prefix のファイル数が、`excl.json` の `files[].path` で 0 になっている。Rust のファイル内 `#[cfg(test)] mod tests` は glob では外せないので、手順 4 の分類でテストとして扱う

4. `excl.json` の `files[].functions[]`（`name` / `kind` / `line` / `cognitive` / `cyclomatic`）から triage 対象を出す。`--top-cognitive` を付けると出力の形が `{metric, top[], summary}` に変わるので、全件の集計には付けない。

   ```bash
   jq '[.files[] | .path as $p | .functions[] | select(.cognitive > 15) | {path: $p, name, line, cognitive, cyclomatic}]' tmp/cccc/excl.json
   ```

   完了条件: この出力の全件を、下の「読み方」の分類（本物 / ノイズ / 誤判定 / テスト）に振り分け、分類ごとの件数と各件の根拠を報告している

分割の実施は `refactoring` へ渡す。

## 読み方

- 同名呼び出しの再帰扱い（誤判定）: 関数と同じ名前の関数・メソッド・関連関数の呼び出しを、再帰として 1 回ごとに +1 する。builder の `fn build` 内の `x.build()`、`fn new` 内の `Vec::new()`、`fn default` 内の `Bar::default()`、`toString()` 内の `this.a.toString()` などが該当し、TS でも Rust でも起きる。見分ける手がかりは、cyclomatic の絶対値が小さいこと、つまり分岐がほぼ無いのに cognitive だけが高いことである。本体の同名呼び出しを数え、cognitive との差が埋まることを確かめる
- dispatcher: フラットな `switch` / `match` は cyclomatic だけを押し上げ、cognitive は +1 に留まる。cognitive の上位にいる dispatcher は case 内の入れ子が原因なので、dev 専用（IPC モックなど）なら除外し、本番なら case 単位で中身を見る
- 他ツールとの差: biome の `noExcessiveCognitiveComplexity` とは、同じ関数でも値が食い違う。しきい値をツール間で流用しない

## 採用判断

- gate より report を先に: 既存コードには `--max-cognitive` の超過がまず出るので、いきなり gate にすると最初から落ちる。人が triage する report タスクとして入れ、gate 化は baseline の仕組みと誤判定の扱いが決まってからにする。`--max-cognitive N` は N を超えたときだけ非ゼロで終わり、stderr には何も出さないので、違反した関数は JSON から取り出す
- 既存 lint との関係: biome の `noExcessiveCognitiveComplexity` は、既定では `info` の opt-in ルールである。clippy の `cognitive_complexity` は `restriction` で既定無効で、clippy は代わりに `excessive_nesting` / `too_many_lines` を挙げている（`cargo clippy --explain cognitive_complexity`）。Rust で関数単位の cognitive 値とランキングが要るときに cccc が役に立つ
- 全量を毎回走査してよい速さなので、差分だけを測る仕組みや `--cache` は、遅さを実測してから検討する
