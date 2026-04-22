---
name: tauri-dev-screenshot
description: Use when a Windows Tauri or embedded WebView app is already running and Codex needs deterministic HWND-based screenshots for layout debugging, visual state comparison, or display breakage checks inside the current workspace.
---

# Tauri Dev Screenshot

## Overview

Capture a running Tauri window on Windows and save it to `<project-root>/tmp/screenshots` as a timestamped PNG.

Use the bundled PowerShell script for deterministic capture and machine-readable JSON output.

Prefer direct HWND capture whenever possible. The script resolves a target window to an HWND and captures it with `PrintWindow`, so overlapping windows do not leak into the PNG the way `CopyFromScreen` would.

## When to Use

- Windows で起動済みの Tauri dev アプリや埋め込み WebView を撮りたい
- レイアウト崩れ、描画欠け、before/after 比較を PNG で残したい
- 他ウィンドウに隠れていても安定して取得したい

Use a different tool when:

- アプリ起動そのものがまだできていない
- ウィンドウ待機、前面化、クリック操作まで必要
- macOS / Linux で同様の取得をしたい

## Command Setup

Resolve the bundled script from the deployed skill root instead of assuming the current directory is the skill folder:

```powershell
$skillRoot = Join-Path $HOME ".agents/skills/tauri-dev-screenshot"
$script = Join-Path $skillRoot "scripts/capture-tauri-window.ps1"
```

## Selector Order

1. Prefer `-WindowHandle` for repeatable captures.
2. Use `-TitleContains` when you need lightweight discovery.
3. Use `-ActiveWindow` only for manual debugging when the target app is already focused.

Rules:

- Specify exactly one of `-WindowHandle`, `-TitleContains`, or `-ActiveWindow`.
- Add `-ClientArea` only when you want the content area without window chrome.
- Stop with an error when multiple visible windows match `-TitleContains`.
- Do not start `tauri dev`, wait for a window, or bring a window to the front in this skill.

## Quick Start

Prefer direct window-handle capture for repeatable, occlusion-safe screenshots:

```powershell
$hwnd = (Get-Process | Where-Object { $_.MainWindowTitle -like "*My Tauri App*" } |
  Select-Object -First 1 -ExpandProperty MainWindowHandle)

powershell -ExecutionPolicy Bypass -File $script `
  -ProjectRoot C:\path\to\project `
  -WindowHandle $hwnd
```

Use `-ClientArea` when you want only the webview/content area without window chrome:

```powershell
powershell -ExecutionPolicy Bypass -File $script `
  -ProjectRoot C:\path\to\project `
  -WindowHandle $hwnd `
  -ClientArea
```

Use title matching when HWND discovery is inconvenient:

```powershell
powershell -ExecutionPolicy Bypass -File $script `
  -ProjectRoot C:\path\to\project `
  -TitleContains "My Tauri App"
```

Use the active window only for manual debugging when the target app is already focused:

```powershell
powershell -ExecutionPolicy Bypass -File $script `
  -ProjectRoot C:\path\to\project `
  -ActiveWindow
```

Add `-Label` to make saved states easier to scan:

```powershell
powershell -ExecutionPolicy Bypass -File $script `
  -ProjectRoot C:\path\to\project `
  -TitleContains "My Tauri App" `
  -Label settings-open
```

## Selector Reference

| Flag             | Use for                  | Notes                                          |
| ---------------- | ------------------------ | ---------------------------------------------- |
| `-WindowHandle`  | Stable automation        | Best default once the target HWND is known     |
| `-TitleContains` | Quick discovery          | Case-insensitive partial match                 |
| `-ActiveWindow`  | Manual local debugging   | Only when the target window is already focused |
| `-ClientArea`    | Chrome-free capture      | Returns only the content area                  |
| `-Label`         | Human-readable filenames | Sanitized before being added to the PNG name   |

## Output Contract

Always emit a single JSON object.

Success shape:

```json
{
  "ok": true,
  "savedPath": "C:\\repo\\tmp\\screenshots\\20260402-231455-home.png",
  "windowTitle": "My App",
  "windowHandle": "0x0000000000123456",
  "selector": "window-handle",
  "captureArea": "client",
  "captureMethod": "print-window",
  "timestamp": "2026-04-02T23:14:55.0000000+09:00",
  "bounds": { "left": 100, "top": 80, "width": 1280, "height": 900 }
}
```

Failure shape:

```json
{
  "ok": false,
  "code": "invalid_window_handle",
  "message": "WindowHandle '0xDEADBEEF' is not valid.",
  "selector": "window-handle",
  "windowHandle": "0xDEADBEEF"
}
```

Failure codes:

- `invalid_selector`
- `invalid_window_handle`
- `window_not_found`
- `multiple_windows_matched`
- `window_not_visible`
- `capture_failed`
- `save_failed`

`multiple_windows_matched` may include a `matches` array of candidate titles and handles.

## Failure Handling

- `invalid_selector`: selector flags are missing or multiple were provided
- `invalid_window_handle`: the supplied HWND is empty, malformed, dead, or non-positive
- `window_not_found`: no matching window was found
- `multiple_windows_matched`: title matching found more than one visible candidate
- `window_not_visible`: the match exists but is minimized, hidden, or zero-sized
- `capture_failed`: `PrintWindow` or bitmap capture failed
- `save_failed`: project root or output directory could not be used

## Script Notes

- Use PowerShell + .NET + Win32 + DWM only.
- Resolve selectors to an HWND, then capture with `PrintWindow` instead of `CopyFromScreen`.
- Capture only visible, non-minimized, non-zero-size top-level windows.
- Use extended frame bounds for whole-window capture and client rect bounds for `-ClientArea`.
- Save PNG files under `<project-root>/tmp/screenshots`.
- Sanitize `-Label` before adding it to the filename.
- Return clear failure reasons instead of throwing raw PowerShell errors.
