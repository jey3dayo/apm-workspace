# GitHub review API

pending review の作成・追記・照合・提出で使う呼び方。仕様の正本は GitHub の [REST: Pull request reviews](https://docs.github.com/en/rest/pulls/reviews) と [GraphQL: pulls](https://docs.github.com/en/graphql/reference/pulls)。

## 既存の pending review を探す

```sh
gh api repos/<owner>/<repo>/pulls/<n>/reviews --paginate \
  --jq '.[] | select(.state == "PENDING" and .user.login == "<me>") | [.id, .commit_id]'
```

GraphQL で追記・差し替えに使う node id は `repository.pullRequest.reviews(states: PENDING)` の `id`（REST の `id` とは別）。

## 作成

```sh
gh api repos/<owner>/<repo>/pulls/<n>/reviews --method POST --input review.json
```

- `review.json`: `commit_id`（head SHA）、`body`、`comments[]`。`event` を省くと PENDING になる
- `comments[]` の各要素: `path`、`body`、`line`、`side`（`RIGHT` が追加側）。範囲なら `start_line` と `start_side` も入れる
- 本文に改行やコードを含むなら、JSON はスクリプトで生成する（シェルの here-doc でエスケープしない）

## 既存の pending review への追記・差し替え

REST には追記の手段がない。

- 追記: GraphQL `addPullRequestReviewThread(input: {pullRequestReviewId, path, line, side, body})`。範囲なら `startLine` / `startSide`
- 本文の差し替え: `updatePullRequestReview`
- コメントの差し替え: `updatePullRequestReviewComment`。本文しか変えられないので、位置を直すときは削除して `addPullRequestReviewThread` で付け直す
- コメントの削除: `deletePullRequestReviewComment(input: {id})`。`id` は REST の `node_id`
- review の削除: `deletePullRequestReview(input: {pullRequestReviewId})`。削除の前に本文と残すコメントを保存する
- `gh api graphql` の変数は型で渡し分ける。文字列は `-f path=...`、数値（`line` / `startLine`）は `-F line=42`、本文をファイルから読むなら `-F body=@file`

## 照合

過不足は REST で見る。review 単位のコメント一覧は、既存スレッドへの返信も含めて review に属するコメントを全件返す。

```sh
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<id>/comments --paginate \
  --jq '.[] | [.id, .path, (.position | tostring), .body] | @json'
```

pending のコメントは `line` / `side` が null で返り、`position` は diff 内の位置でしかない。行・side・範囲は GraphQL の `reviewThreads` を全ページ取得し、コメントごとの review で絞る。

```sh
gh api graphql --paginate -f owner=<owner> -f repo=<repo> -F n=<n> -f query='
query($owner: String!, $repo: String!, $n: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $n) {
    reviewThreads(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { path line startLine diffSide startDiffSide isOutdated
        comments(first: 100) { nodes { databaseId pullRequestReview { databaseId } } } }
    }
  } }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[]
  | select(any(.comments.nodes[]; .pullRequestReview.databaseId == <id>))'
```

REST で得たコメント id の集合が、GraphQL で位置を取れたコメント（`databaseId`）の集合と一致することを確かめる。thread の `line` が null か `isOutdated` が true なら、差分上の意図した行に付いていない。pending のスレッドがこの一覧に出ることは未確認。出なければ review 側からコメントの位置を取る。

```sh
gh api graphql -f owner=<owner> -f repo=<repo> -F n=<n> -f query='
query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $n) {
    reviews(states: PENDING, first: 10) { nodes { databaseId
      comments(first: 100) { nodes { databaseId path line startLine outdated } } } }
  } }
}' --jq '.data.repository.pullRequest.reviews.nodes[] | select(.databaseId == <id>) | .comments.nodes[]'
```

ここで pending の `line` が null 以外で返るかも未確認。`PullRequestReviewComment` には side の項目が無いので、この経路では side を確かめられない。この経路で照合したコメントは全件、PR の画面で side と行を確かめ、確かめるまで提出しない。

## 提出

```sh
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<id> --jq .body > tmp/<pr>-review/body.md
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<id>/events --method POST \
  -f event=COMMENT -F body=@tmp/<pr>-review/body.md
```

`body` は §4 で組み立てた本文を上書きするので、取得した現在の本文をそのまま渡す。`COMMENT` / `REQUEST_CHANGES` では本文が必須。`event` は `APPROVE` / `COMMENT` / `REQUEST_CHANGES`。提出後に `pulls/<n>/reviews/<id>` を取得し、`state` と `submitted_at` を確かめる。
