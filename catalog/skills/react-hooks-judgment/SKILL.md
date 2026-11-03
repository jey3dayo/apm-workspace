---
name: react-hooks-judgment
description: >-
  Choosing React hooks and deciding when not to use one: values computed during render, key resets, URL state,
  useEffect anti-patterns (You Might Not Need an Effect), React 19 Actions with useOptimistic / useActionState /
  useFormStatus, use + Suspense data reads, useEffectEvent limits, state placement and Suspense boundaries,
  React Compiler memoization defaults, and the eslint-plugin-react-hooks recommended gate.
---

# React Hooks Judgment

React コンポーネントを書く・直す・レビューするときに「どの hook を使うか」「そもそも hook が要るか」を決めるための判断基準。
API の正本は react.dev で、ここには判断の順序と落とし穴だけを置く。

## 棲み分け

- このスキル: hook の選択、Effect の要否、React 19 の非同期 hook、state の置き場と Suspense 境界、完了ゲート
- パフォーマンス規則（waterfall、bundle、再レンダー削減、SSR）: `react-best-practices`（外部スキル）。本文は写さず、規則 ID で参照する
- 変更後の健全性スコア・診断: `react-doctor`
- 先に `package.json` / lockfile で React と eslint-plugin-react-hooks のバージョンを確かめる。React 18 以前なら React 19 の節を使わない。`useEffectEvent` は 19.2 以降、`useOptimistic` / `useActionState` / `useFormStatus` / `use` は 19.0 以降

## 判断の順序

1. state が要るか。レンダー中に計算できる、`key` でリセットできる、URL が正本になる、のどれかなら state を作らない
2. 要るなら目的に合う最小の hook を選ぶ → [references/hook-selection.md](references/hook-selection.md)
3. `useEffect` を書く前に [references/effect-checklist.md](references/effect-checklist.md) を全部通す
4. 更新系の非同期処理・フォーム・データ取得は [references/async-patterns.md](references/async-patterns.md)
5. state の置き場と Suspense 境界を決める（下の「設計」）
6. lint ゲートを通す（下の「完了条件」）

## 早見表

| 状況                                         | 選ぶ                                         | 避ける                               |
| -------------------------------------------- | -------------------------------------------- | ------------------------------------ |
| props / state から計算できる値               | レンダー中に計算                             | `useState` + `useEffect` で同期      |
| prop が変わったら子の state を全部戻す       | 子に `key` を渡す                            | Effect の中で `setState`             |
| 共有・リロード・戻るで復元したい UI 状態     | URL（router の search params）               | `useState` だけで持つ                |
| 入力に重い一覧描画が引きずられる             | `useDeferredValue`                           | 固定ミリ秒のデバウンス（描画が原因） |
| 送信結果を待たずに画面へ反映                 | `useOptimistic`（setter は Action 内で呼ぶ） | 手書きの rollback 用 state           |
| フォーム送信の結果・エラー・pending          | `useActionState`                             | `useState` + `onSubmit` + `loading`  |
| 送信ボタンだけが pending を知りたい          | `<form>` の子で `useFormStatus`              | `isPending` を props で配る          |
| ブラウザ API や外部ストアの購読              | `useSyncExternalStore`                       | `useEffect` + `setState`             |
| 読み取り系のデータ取得                       | framework / キャッシュ済み Promise + `use`   | cleanup のない `useEffect` + `fetch` |
| 外部システムとの同期（接続、購読、DOM 連携） | `useEffect`（理由コメント付き）              | —                                    |

## 設計

- state は使う場所に最も近い共通の親に置く。2 つの state を同期させたくなったら 1 つにまとめて持ち上げる
- 選択状態はオブジェクトではなく ID を持ち、表示用の値はレンダー中に引く
- サーバー由来のデータを state に複製しない。キャッシュ層・Server Component・framework の loader を正本にする
- Suspense 境界は「同時に出てほしい単位」ごとに置く。独立して遅い部分は別の境界に分け、ページ全体を 1 つの fallback で覆わない
- 表示済みの内容を fallback に戻したくない更新は Transition にする（`startTransition` / `useDeferredValue`）
- Promise の reject は最寄りの Error Boundary に出るので、Suspense 境界とエラー境界は組で設計する
- Transition は中断の単位がコンポーネントなので、重い描画は小さいコンポーネントに分ける
- React Compiler（v1.0 以降）を使うプロジェクトでは、新規コードに `useMemo` / `useCallback` / `memo` を既定で書かない。Effect の依存を精密に制御したいときだけ escape hatch として使う
- 既存の手書きメモ化は、外すとコンパイル結果が変わる。テストで挙動を確かめずに消さない
- Compiler を使っていないプロジェクトのメモ化判断は `react-best-practices` の `rerender-*` 規則に従う

## 完了条件（lint ゲート）

- eslint-plugin-react-hooks 7.x の `recommended` を有効にし、変更したファイルに違反がない状態を完了とする
  - flat config は `reactHooks.configs.flat.recommended`、旧形式は `plugin:react-hooks/recommended`
  - 7.x からは Compiler 由来の規則（`set-state-in-effect`、`refs`、`purity`、`immutability`、`static-components` など）も含まれる。Compiler を入れていなくても効く
- 違反が出たら、無効化コメントや依存配列の削除で黙らせない。[references/effect-checklist.md](references/effect-checklist.md) に戻り、Effect や state がそもそも要るかから見直す
- `exhaustive-deps` を黙らせる目的の `useEffectEvent` や ref 退避は、違反を隠しているだけとみなす
- プロジェクトに plugin が入っていない・6.x 以前なら、導入は依存の追加にあたる。勝手に入れず、提案として報告する

## 出典

- [You Might Not Need an Effect](https://react.dev/learn/you-might-not-need-an-effect) / [Separating Events from Effects](https://react.dev/learn/separating-events-from-effects)
- [eslint-plugin-react-hooks](https://react.dev/reference/eslint-plugin-react-hooks) / [React Compiler v1.0](https://react.dev/blog/2025/10/07/react-compiler-1)
- [useOptimistic](https://react.dev/reference/react/useOptimistic) / [useActionState](https://react.dev/reference/react/useActionState) / [use](https://react.dev/reference/react/use) / [useFormStatus](https://react.dev/reference/react-dom/hooks/useFormStatus)
- uhyo「[Async React時代の宣言的UI: デバウンスの例](https://zenn.dev/uhyo/articles/async-react-debounce)」「[useEffectからfetchするときのベストプラクティス](https://qiita.com/uhyo/items/dec319ced85fc1b83f86)」
- 比較したスキル（文面は取り込んでいない）: [react-best-practices](https://github.com/vercel-labs/agent-skills/tree/main/skills/react-best-practices)、[react-useeffect](https://github.com/davila7/claude-code-templates/blob/main/cli-tool/components/skills/development/react-useeffect/SKILL.md)、[use-effect-killer](https://github.com/victor36max/use-effect-killer)
