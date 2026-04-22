---
name: tauri-icon-gen
description: "Use when an existing app image should be converted into Tauri-ready icons, including transparency cleanup, square source normalization, and `pnpm tauri icon` generation. Do not use for skill directory moves, path fixes, distribution, or marketplace packaging even if the path contains `tauri-icon-gen`; use `skill-creator` instead."
version: 1.0.0
tags: [tauri, icon, png, transparency, image-processing]
triggers:
  - アイコン生成
  - アイコン変換
  - 透過PNG
  - tauri icon
  - app icon
---

# Tauri App Icon Generation

Tauri アプリ用のアイコン生成ワークフロー。ソース画像の白背景除去から全プラットフォーム向けアイコン一式の生成まで。

## First Step

作業の最初に、リポジトリルートへ移動し、入力画像が正方形かどうか確認する。非正方形なら、先に余白追加やトリミングで正方形化してから進める。

Codex では bundled script の root を `~/.agents/skills` として扱う。

```bash
SKILL_ROOT="$HOME/.agents/skills/tauri-icon-gen"
cd /path/to/tauri-project
```

## Prerequisites

- Python 3 + Pillow (`pip install Pillow`)
- pnpm + Tauri CLI (`pnpm tauri icon`)

## Workflow

### Step 0: ソース画像を正方形にする

- Tauri の元画像は正方形前提で扱う
- 非正方形画像は、この skill の script では補正しない
- 必要なら画像編集ツールや別コマンドで余白を足し、中心を保った正方形 PNG にする

### Step 1: ソース画像の透過化

白背景のソース PNG をアルファ透過に変換する。

```bash
python3 "$SKILL_ROOT/scripts/remove_white_bg.py" <input.png> [output.png]
```

- `threshold=235`: この値以上の RGB は完全透過 (alpha=0)
- `soft_threshold=215`: threshold 未満でもこの値以上なら半透過（エッジのスムージング）
- output を省略すると input を上書き

### Step 2: 透過確認

```bash
sips -g hasAlpha <output.png>
```

`hasAlpha: yes` であることを確認。目視でも透過が正しいか確認する。

### Step 3: Tauri アイコン一式生成

```bash
pnpm tauri icon <source.png>
```

`pnpm tauri icon` は Tauri プロジェクトのルートで実行する。

生成先: `src-tauri/icons/`

生成されるもの:

- PNG: 32x32, 64x64, 128x128, 128x128@2x, icon.png (512x512)
- ICNS: macOS 用 (icon.icns)
- ICO: Windows 用 (icon.ico)
- iOS: AppIcon 各サイズ
- Android: mipmap 各密度
- Windows Store: Square ロゴ各サイズ

### Step 4: 生成結果確認

```bash
sips -g hasAlpha -g pixelWidth -g pixelHeight src-tauri/icons/icon.png
```

## Typical Usage (Ultra RSS Reader)

```bash
SKILL_ROOT="$HOME/.agents/skills/tauri-icon-gen"
cd /path/to/tauri-project

# ダーク版アイコンの白背景を除去
python3 "$SKILL_ROOT/scripts/remove_white_bg.py" assets/app-icon.png

# ライト版も同様
python3 "$SKILL_ROOT/scripts/remove_white_bg.py" assets/app-icon-light.png

# ダーク版をメインアイコンとして全プラットフォーム向けに生成
pnpm tauri icon assets/app-icon.png

# 確認
sips -g hasAlpha src-tauri/icons/icon.png
```

## Notes

- ソース画像は 1024x1024 以上を推奨（Tauri が各サイズにリサイズ）
- macOS の `.icns` と Windows の `.ico` も自動生成される
- 元画像が既に透過であれば Step 1 はスキップ可
- Pillow がない場合: `pip install Pillow`
