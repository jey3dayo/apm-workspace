# Mole Cleanup Reference

## Local Notes

- Mole was installed by Homebrew as `/opt/homebrew/Cellar/mole/1.38.0`.
- The linked `mo` command may conflict with another `mo` binary. Use `/opt/homebrew/opt/mole/bin/mo` for Mole.
- Mole's whitelist loader checks `$HOME/.config/mole/whitelist`.
- When that whitelist file exists, Mole does not merge it with the internal defaults. The local whitelist must include any default protections that should remain active.

## Current Protection Policy

Keep these categories protected from broad cleanup:

- Browser caches and profiles: Google Chrome, Arc, Vivaldi, Brave, Dia, Firefox.
- Docker Desktop container and VM state. Prune Docker through Docker commands, not broad file deletion.
- Claude VM bundles.
- CleanShot media.
- Local model files such as Ollama and app-specific models.
- iCloud Mobile Documents and macOS metadata caches.

## High-Signal Cleanup Categories

These have been useful on this machine, but still require confirmation before deletion:

- Homebrew cache and downloads.
- Playwright browser cache at `$HOME/Library/Caches/ms-playwright`.
- Docker build cache and unused images via Docker CLI.
- Application leftovers only after verifying the app is uninstalled and the paths are not user data.

## Mole Default Whitelist Patterns to Preserve

If maintaining a custom whitelist, preserve Mole's internal defaults explicitly:

```text
$HOME/Library/Caches/ms-playwright*
$HOME/.cache/huggingface*
$HOME/.m2/repository/*
$HOME/.gradle/caches/*
$HOME/.gradle/daemon/*
$HOME/.ollama/models/*
$HOME/Library/Caches/com.nssurge.surge-mac/*
$HOME/Library/Application Support/com.nssurge.surge-mac/*
$HOME/Library/Caches/org.R-project.R/R/renv/*
$HOME/Library/Caches/pypoetry/virtualenvs*
$HOME/Library/Caches/JetBrains*
$HOME/Library/Caches/com.jetbrains.toolbox*
$HOME/Library/Caches/tealdeer/tldr-pages
$HOME/Library/Application Support/JetBrains*
$HOME/Library/Caches/com.apple.finder
$HOME/Library/Mobile Documents*
$HOME/Library/Caches/com.apple.FontRegistry*
$HOME/Library/Caches/com.apple.spotlight*
$HOME/Library/Caches/com.apple.Spotlight*
$HOME/Library/Caches/CloudKit*
FINDER_METADATA
```

## Reporting Template

```text
削除は実行していません。dry-run では以下が候補です:
- <category>: <examples / size if available>

保護中:
- <protected categories>

次に消すなら:
1. <lowest-risk target>
2. <requires confirmation target>
```
