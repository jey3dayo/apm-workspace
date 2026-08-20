[CmdletBinding()]
param(
  [Parameter(Position = 0, Mandatory = $true)]
  [ValidateSet("save", "restore")]
  [string]$Command
)

# PowerShell port of agmsg-state.sh. Windows is not treated as bash-only, so
# the save/restore/absorb contract (roster kept outside the deploy target,
# re-linked via symlink rather than copied back and forth) is re-implemented
# here rather than shelling out to bash. See agmsg-state.sh's header comment
# for the underlying rationale.
#
# Contract kept identical to the bash version:
#   - save/restore never delete a runtime dir whose copy into the store
#     failed; the dir is left in place and the command exits non-zero.
#   - restore never falls back to copying when the roster symlink can't be
#     created (e.g. missing privilege on Windows) — it warns and exits
#     non-zero instead, because the roster is only ever meant to exist as a
#     symlink.

$ErrorActionPreference = "Stop"

function Write-WarnLine {
  param([string]$Message)
  Write-Warning $Message
}

function Write-ErrorLine {
  param([string]$Message)
  [Console]::Error.WriteLine($Message)
}

$StateRoot = if ($env:XDG_STATE_HOME) { Join-Path $env:XDG_STATE_HOME "agmsg" } else { Join-Path $HOME ".local/state/agmsg" }
$SkillDir = Join-Path $HOME ".agents/skills/agmsg"
$RuntimeDirNames = @("db", "teams")

function Test-ReparsePoint {
  param([Parameter(Mandatory = $true)][string]$Path)

  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) {
    return $false
  }
  return [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

# Copies files that don't already exist at the destination, mirroring `cp -Rn`:
# an existing store file stays authoritative, and only a genuine copy error
# (not "already exists") is treated as a failure.
function Copy-NewOnlyRecursive {
  param(
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [Parameter(Mandatory = $true)][string]$DestDir
  )

  $errors = New-Object System.Collections.Generic.List[string]
  $sourceRoot = (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

  Get-ChildItem -LiteralPath $SourceDir -Recurse -Force -File | ForEach-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $destPath = Join-Path $DestDir $relative

    if (Test-Path -LiteralPath $destPath) {
      return
    }

    try {
      $destParent = Split-Path -Parent $destPath
      New-Item -ItemType Directory -Path $destParent -Force -ErrorAction Stop | Out-Null
      Copy-Item -LiteralPath $_.FullName -Destination $destPath -ErrorAction Stop
    }
    catch {
      $errors.Add($_.Exception.Message)
    }
  }

  return $errors
}

# Moves a runtime dir that is still a plain directory into the store, leaving
# the deploy target free for the symlink. Returns $true on success (including
# "nothing to do"), $false when a real copy error left the target in place.
function Invoke-AbsorbPlainDir {
  param([Parameter(Mandatory = $true)][string]$Name)

  $target = Join-Path $SkillDir $Name
  $store = Join-Path $StateRoot $Name

  if (-not (Test-Path -LiteralPath $target -PathType Container)) {
    return $true
  }
  if (Test-ReparsePoint -Path $target) {
    return $true
  }

  New-Item -ItemType Directory -Path $store -Force | Out-Null

  $errors = Copy-NewOnlyRecursive -SourceDir $target -DestDir $store
  if ($errors.Count -gt 0) {
    Write-ErrorLine ("agmsg-state: failed to absorb {0} into {1}, leaving {0} in place: {2}" -f $target, $store, ($errors -join "; "))
    return $false
  }

  Remove-Item -LiteralPath $target -Recurse -Force
  return $true
}

switch ($Command) {
  "save" {
    $failed = $false
    foreach ($name in $RuntimeDirNames) {
      if (-not (Invoke-AbsorbPlainDir -Name $name)) {
        $failed = $true
      }
    }
    # Callers invoking this script via `&` (apm-workspace.ps1's Invoke-Apply
    # et al.) read $LASTEXITCODE to detect failure. PowerShell only sets that
    # from an explicit `exit`, not from a script simply completing — falling
    # off the end here would leave $LASTEXITCODE at whatever a prior native
    # command left it at, masking success as a stale failure.
    if ($failed) {
      exit 1
    }
    exit 0
  }

  "restore" {
    if (-not (Test-Path -LiteralPath $SkillDir -PathType Container)) {
      Write-WarnLine "agmsg not deployed at $SkillDir — skipping relink."
      exit 0
    }

    $failed = $false
    foreach ($name in $RuntimeDirNames) {
      $store = Join-Path $StateRoot $name
      New-Item -ItemType Directory -Path $store -Force | Out-Null

      if (-not (Invoke-AbsorbPlainDir -Name $name)) {
        $failed = $true
        continue
      }

      $target = Join-Path $SkillDir $name
      # Repoint even when a link exists, so a stale target is corrected.
      if (Test-ReparsePoint -Path $target) {
        Remove-Item -LiteralPath $target -Force
      }

      try {
        New-Item -ItemType SymbolicLink -Path $target -Target $store -ErrorAction Stop | Out-Null
        Write-Host "agmsg $name linked: $target -> $store"
      }
      catch {
        # No copy fallback here on purpose: the roster is only ever meant to
        # exist as a symlink, unlike the private-skill symlinks elsewhere in
        # this workspace, which do fall back to a copy.
        Write-WarnLine "agmsg-state: failed to symlink $target -> $store : $($_.Exception.Message)"
        $failed = $true
      }
    }
    if ($failed) {
      exit 1
    }
    exit 0
  }
}
