# Async Patterns (React 19)

React 19 以降の前提。Action は `startTransition` に渡した関数、または `action` / `formAction` など Action prop に渡した関数のこと。

## useOptimistic の setter は Action の中で呼ぶ

- hook 自体は他の hook と同じくトップレベルで呼ぶ。Action の中で呼ぶのは返された setter
- setter は `startTransition` の中か Action prop の中でだけ呼ぶ。外で呼ぶと開発時に警告が出て、楽観値が一瞬しか出ない
- レンダー中に setter を呼ぶのはエラー
- Action が終わると楽観値は本当の値に置き換わる。失敗したら元の値に戻るので、rollback 用の state を自分で持たない
- Action の実行中に元の値が別の理由で変わりうるなら、`useOptimistic(value, reducer)` の reducer 形にして、最新の元の値に楽観的な差分を適用する
- 失敗時に「戻る」ことがユーザーに誤解を与える操作（支払い、取り消せない削除）には使わない

## フォームは useActionState

- `const [state, dispatchAction, isPending] = useActionState(reducerAction, initialState)`
- `<form action={dispatchAction}>` に渡すと送信が自動で Transition になる。手で呼ぶなら `startTransition` で包む（包まないと `isPending` が更新されない）
- `reducerAction` の引数は `(前回の state, payload)`。フォームから呼ぶと `FormData` は 2 番目に来る
- 想定内のエラー（入力不正、在庫切れ）は戻り値の state に入れて表示する。想定外のエラーは throw して Error Boundary に任せる。throw すると後続のキュー済み呼び出しも捨てられる
- 呼び出しは順番に処理される。並列にしたい操作には向かない（`useState` + `useTransition` を使う）
- 即時の反映が要るなら `useOptimistic` と組み合わせる
- 送信ボタンの pending だけが要るなら、ボタンを別コンポーネントにして `useFormStatus` を使う
- `await` の後に別の state を更新するときは、その更新も `startTransition` で包む（現時点の制約）

## データ取得は use + Suspense

- 読み取り系のデータは、Server Component や framework の loader、キャッシュから受け取った Promise を `use` で読む
- Client Component のレンダー中に Promise を作らない。作り直されるたびに fallback に戻る
- `use` は try-catch の中で呼べない。失敗は Error Boundary で受ける
- 取得の開始はできるだけ上（ルートや親）で行い、読むのは使う場所で行う。親で `await` してから描画すると、子の取得と直列になる（waterfall の詳細は `react-best-practices` の `async-*` 規則）
- 境界の置き方は SKILL.md の「設計」を参照

## useEffectEvent（React 19.2 以降で安定）

- 使う場面: Effect の中のタイマーやリスナーから最新の props / state を読みたいが、その値の変化で接続し直したくない
- 呼べるのは Effect と他の Effect Event の中だけ。レンダー中に呼ばない、子コンポーネントや他の hook に渡さない
- 依存配列に入れない。identity は意図的に毎回変わる
- 依存を減らすための道具ではない。Effect が本当にその値に反応すべきなら依存に入れる。「この値が変わっても再実行しない」と説明できるときだけ使う
- イベントハンドラや子に渡すコールバックには普通の関数を使う
