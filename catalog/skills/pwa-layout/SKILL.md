---
name: pwa-layout
description: >-
  PWA・ホーム画面起動（standalone / fullscreen）でフッターや固定要素がずれる・
  ノッチやホームインジケーターに重なる・Safari タブでは正常なのにインストール後だけ崩れる、
  といったレイアウト問題の診断と修正。env(safe-area-inset-*)、viewport-fit=cover、
  manifest の display、100vh 問題（dvh / svh）、キーボード重なり（visualViewport /
  interactive-widget）、@media (display-mode) によるスコープを扱う。
---

# PWA Layout

## 仕組み（診断の前提）

- manifest の `display: standalone` / `fullscreen` でブラウザ UI が消え、ページがノッチ・ホームインジケーター領域まで届く。Safari タブ内ではブラウザ UI 自体が緩衝になるため、崩れは**インストール後の起動でだけ再現する**のが正常な挙動。
- `env(safe-area-inset-*)` は viewport meta に `viewport-fit=cover` が無いと**全デバイスで 0** を返す。「env() を書いたのに効かない」の最頻原因はこれ。
- Android 15 以降は edge-to-edge レイアウトが既定になり、OS が自動確保していた余白が消えるため `env()` 対応の必須度が上がっている。inset の実値はメーカー・OS・ナビゲーションモードでばらつき、**3 ボタンナビでは 0 が正しい値**のこともある（対応漏れと誤診しやすい）。

## 診断

| 症状                                               | 原因                                            | 修正                                          |
| -------------------------------------------------- | ----------------------------------------------- | --------------------------------------------- |
| フッター・ボトムナビがホームインジケーターに重なる | 下端要素に `safe-area-inset-bottom` が未適用    | パターン 2                                    |
| `env()` を書いたのに値が 0 のまま                  | viewport meta に `viewport-fit=cover` が無い    | パターン 1                                    |
| Safari タブでは正常、ホーム画面起動でだけずれる    | standalone でブラウザ UI の緩衝が消えた（仕様） | パターン 1〜2、PWA 限定調整はパターン 5       |
| 画面下が切れる・`100vh` がはみ出す                 | iOS の `vh` は動的 UI を含む                    | パターン 4                                    |
| キーボード表示で入力欄・フッターが隠れる           | キーボードは safe-area に含まれない             | パターン 6                                    |
| 横向きでノッチ側に重なる・不自然な余白             | left / right inset が未適用                     | パターン 3                                    |
| ステータスバー裏・inset 領域の背景が抜ける         | 背景を持つ要素が inset 領域まで届いていない     | パターン 2 の padding 方式（margin にしない） |

## 修正パターン

1. viewport meta（すべての前提）:

   ```html
   <meta
     name="viewport"
     content="width=device-width, initial-scale=1, viewport-fit=cover"
   />
   ```

2. 固定フッター / ボトムナビ: `margin` ではなく `padding` で確保する。要素自身の背景が inset 領域を塗るため。`max()` で inset が 0 の端末にも通常余白を残す。

   ```css
   .bottom-nav {
     padding-bottom: max(12px, env(safe-area-inset-bottom));
   }
   ```

   Tailwind は任意値でそのまま書ける: `pb-[max(12px,env(safe-area-inset-bottom))]`。

   Android の伸縮ナビバーでは `safe-area-inset-bottom` がスクロール中に動的に変わり、fixed 要素の高さ計算に直接使うとリフローで性能劣化する。Chrome 135+ は静的な最大値 `env(safe-area-max-inset-bottom)` を提供しており、動的値と組み合わせて位置ずれなしに固定できる:

   ```css
   .bottom-nav {
     position: fixed;
     bottom: calc(
       env(safe-area-inset-bottom, 0px) - env(safe-area-max-inset-bottom, 36px)
     );
     padding-bottom: env(safe-area-max-inset-bottom, 36px);
   }
   ```

3. 上端・横向き: 固定ヘッダーには `padding-top: env(safe-area-inset-top)`、横向きノッチには `padding-left / padding-right: env(safe-area-inset-left / right)`。全周を扱うレイアウトルートなら 4 辺まとめて当てる。

   iOS でステータスバーの見た目を変える `<meta name="apple-mobile-web-app-status-bar-style">` は `apple-mobile-web-app-capable` の有効化が前提。`black-translucent` はステータスバーを透明化してコンテンツを裏まで描画するため、`env(safe-area-inset-top)` の確保が実質必須になる。iOS は manifest の `display` だけでなくこの meta の併用が前提。

4. 全画面高さ: `100vh` の代わりに `100dvh`（可変 UI 追従）または `100svh`（常に最小値で固定）。旧ブラウザ fallback が要る場合のみ `height: 100vh` を先に書いて上書きする。

5. PWA 起動時だけの調整: `@media (display-mode: standalone), (display-mode: fullscreen)` でスコープする。JS からは `matchMedia('(display-mode: standalone)')`、iOS 旧式判定は `navigator.standalone`。

6. キーボード重なり: Chrome / Android は viewport meta に `interactive-widget=resizes-content` を追加。iOS Safari は meta を無視するため、`visualViewport` の `resize` イベントで `window.innerHeight - visualViewport.height` を計算し、固定要素をオフセットする。

## ラッパー環境・デスクトップ PWA

- Capacitor（Android）の edge-to-edge モードは `env()` のネイティブ値を正しく上書きできない場合がある。`@capacitor-community/safe-area` が JS 注入するカスタム変数を優先し、`var(--safe-area-inset-top, env(safe-area-inset-top, 0px))` の形でフォールバックさせる。React Native は `react-native-safe-area-context` という別レイヤーの API で、CSS の `env()` とは仕組みが異なる。
- デスクトップ PWA でタイトルバー領域をカスタム UI にする場合は manifest の `display_override: ["window-controls-overlay"]`（Chromium 104+）。対応する env 変数は `titlebar-area-x / y / width / height`。

## 検証

- Safari タブでの確認は standalone の再現にならない。 実機または Xcode Simulator で「ホーム画面に追加」してから起動して確認する。
- standalone ページのデバッグは macOS Safari の開発メニューから実機 / シミュレータを remote inspect する。
- inset の実値は `env()` を直接読めないため、適用した要素の computed `padding` を DevTools で読む。値が 0 ならまずパターン 1 を疑う。
