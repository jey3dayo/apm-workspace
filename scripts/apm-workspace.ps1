[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Command = "help",

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceDir = if ($env:APM_WORKSPACE_DIR) { $env:APM_WORKSPACE_DIR } else { Join-Path $HOME ".apm" }
$WorkspaceRepo = if ($env:APM_WORKSPACE_REPO) { $env:APM_WORKSPACE_REPO } else { "https://github.com/jey3dayo/apm-workspace.git" }
$CodexOutput = if ($env:APM_CODEX_OUTPUT) { $env:APM_CODEX_OUTPUT } else { Join-Path $HOME ".codex\AGENTS.md" }
$MiseDestination = Join-Path $WorkspaceDir "mise.toml"
$CatalogBuildRootDir = Join-Path $WorkspaceDir ".catalog-build"
$CatalogDirName = "catalog"

function Test-CommandAvailable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Write-WarnLine {
  param([string]$Message)
  Write-Warning $Message
}

function Write-ErrorLine {
  param([string]$Message)
  Write-Host $Message -ForegroundColor Red
}

function Write-SuccessLine {
  param([string]$Message)
  Write-Host $Message -ForegroundColor Green
}

function Require-Command {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if (-not (Test-CommandAvailable -Name $Name)) {
    throw "$Name not found. Install it first."
  }
}

function Require-Apm {
  if (-not (Test-CommandAvailable -Name "apm")) {
    throw "apm not found. Run 'cd $WorkspaceDir; mise install' (or install it in another shell) before retrying."
  }
}

function Test-SkillId {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  if ([string]::IsNullOrWhiteSpace($SkillId)) {
    throw "Invalid skill id: $SkillId"
  }

  if ($SkillId.Contains("/") -or $SkillId.Contains("\") -or $SkillId -in @(".", "..")) {
    throw "Invalid skill id: $SkillId"
  }

  $segments = @($SkillId -split ':')
  Test-SkillPathSegments -Segments $segments -OriginalValue $SkillId
}

function Get-ExternalSkillRelativePath {
  param(
    [string]$VirtualPath
  )

  if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
    throw "Invalid external skill virtual path: $VirtualPath"
  }

  if ($VirtualPath.StartsWith("skills/")) {
    $relativePath = $VirtualPath.Substring("skills/".Length)
  } elseif ($VirtualPath -match '.*/skills/(?<relative>.+)$') {
    $relativePath = $Matches['relative']
  } else {
    throw "Invalid external skill virtual path: $VirtualPath"
  }

  if ($relativePath -match '^\.[^/]+/(?<rest>.+)$') {
    $relativePath = $Matches['rest']
  }

  if ([string]::IsNullOrWhiteSpace($relativePath)) {
    throw "Invalid external skill virtual path: $VirtualPath"
  }

  $segments = Convert-ReferencePathToSegments -Value $relativePath
  return ($segments -join '/')
}

function Test-SkillPathSegments {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Segments,

    [Parameter(Mandatory = $true)]
    [string]$OriginalValue
  )

  if (-not $Segments -or $Segments.Count -eq 0) {
    throw "Invalid skill path: $OriginalValue"
  }

  foreach ($segment in $Segments) {
    if ($segment -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
      throw "Invalid skill path: $OriginalValue"
    }

    if ($segment -in @(".", "..")) {
      throw "Invalid skill path: $OriginalValue"
    }
  }
}

function Convert-SkillIdToPathSegments {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  $segments = @($SkillId -split ':')
  Test-SkillPathSegments -Segments $segments -OriginalValue $SkillId
  return $segments
}

function Convert-SkillIdToPackageRelativePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  return ((Convert-SkillIdToPathSegments -SkillId $SkillId) -join [System.IO.Path]::DirectorySeparatorChar)
}

function Convert-SkillIdToManifestRelativePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  return ((Convert-SkillIdToPathSegments -SkillId $SkillId) -join "/")
}

function Ensure-WorkspaceRepo {
  Require-Command -Name "git"

  if (-not (Test-Path -LiteralPath $WorkspaceDir)) {
    Write-Host "Cloning $WorkspaceRepo into $WorkspaceDir"
    & git clone $WorkspaceRepo $WorkspaceDir
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to clone $WorkspaceRepo"
    }
  } elseif ((Test-Path -LiteralPath $WorkspaceDir -PathType Container) -and -not (Test-Path -LiteralPath (Join-Path $WorkspaceDir ".git"))) {
    $entries = @(Get-ChildItem -LiteralPath $WorkspaceDir -Force)
    if ($entries.Count -ne 0) {
      throw "$WorkspaceDir exists but is not an empty directory or git checkout."
    }

    Write-Host "Cloning $WorkspaceRepo into existing empty directory $WorkspaceDir"
    Push-Location $WorkspaceDir
    try {
      & git clone $WorkspaceRepo .
      if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone $WorkspaceRepo into $WorkspaceDir"
      }
    }
    finally {
      Pop-Location
    }
  } elseif (-not (Test-Path -LiteralPath $WorkspaceDir -PathType Container)) {
    throw "$WorkspaceDir exists but is not a directory."
  }

  if (-not (Test-Path -LiteralPath (Join-Path $WorkspaceDir ".git"))) {
    throw "$WorkspaceDir exists but is not a git checkout."
  }

}

function Ensure-WorkspaceScaffold {
  Ensure-WorkspaceRepo

  $manifestPath = Join-Path $WorkspaceDir "apm.yml"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing workspace apm.yml: $manifestPath"
  }
}

function Copy-DirectoryContents {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$DestinationDir
  )

  if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "Directory not found: $SourceDir"
  }

  New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
  foreach ($entry in Get-ChildItem -LiteralPath $SourceDir -Force) {
    Copy-Item -LiteralPath $entry.FullName -Destination $DestinationDir -Recurse -Force
  }
}

function Get-RelativeFilePaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RootDir
  )

  if (-not (Test-Path -LiteralPath $RootDir)) {
    return @()
  }

  $rootFullPath = (Resolve-Path -LiteralPath $RootDir).Path
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($file in Get-ChildItem -LiteralPath $RootDir -Recurse -File) {
    $relativePath = $file.FullName.Substring($rootFullPath.Length).TrimStart('\', '/')
    $result.Add(($relativePath -replace '\\', '/'))
  }

  $array = $result.ToArray()
  [Array]::Sort($array)
  return $array
}

function Convert-WorkspaceRemoteToRepoReference {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteUrl
  )

  if ($RemoteUrl -match '^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$') {
    return "$($matches[1])/$($matches[2])"
  }
  if ($RemoteUrl -match '^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$') {
    return "$($matches[1])/$($matches[2])"
  }

  throw "Unsupported workspace remote URL for internal bundle reference: $RemoteUrl"
}

function Get-WorkspaceRemoteUrl {
  param(
    [string]$RemoteName = "origin"
  )

  Ensure-WorkspaceRepo

  $remoteUrl = & git -C $WorkspaceDir remote get-url $RemoteName 2>$null
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($remoteUrl | Out-String))) {
    return ($remoteUrl | Out-String).Trim()
  }

  if ($RemoteName -eq "origin") {
    return $WorkspaceRepo
  }

  throw "Could not resolve remote URL for '$RemoteName'"
}

function Get-WorkspaceRepoReference {
  param(
    [string]$RemoteName = "origin"
  )

  return Convert-WorkspaceRemoteToRepoReference -RemoteUrl (Get-WorkspaceRemoteUrl -RemoteName $RemoteName)
}

function Get-WorkspaceTrackingInfo {
  $currentBranch = & git -C $WorkspaceDir branch --show-current 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($currentBranch | Out-String))) {
    throw "Cannot register internal bundle from a detached HEAD. Check out a tracking branch first."
  }

  $currentBranch = ($currentBranch | Out-String).Trim()
  $remoteName = & git -C $WorkspaceDir config --get "branch.$currentBranch.remote" 2>$null
  $mergeRef = & git -C $WorkspaceDir config --get "branch.$currentBranch.merge" 2>$null

  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($remoteName | Out-String)) -or [string]::IsNullOrWhiteSpace(($mergeRef | Out-String))) {
    throw "Branch '$currentBranch' has no upstream tracking branch. Push it first."
  }

  $remoteName = ($remoteName | Out-String).Trim()
  $mergeBranch = (($mergeRef | Out-String).Trim()) -replace '^refs/heads/', ''
  return [pscustomobject]@{
    RemoteName = $remoteName
    BranchName = $mergeBranch
  }
}

function Refresh-WorkspaceCheckout {
  Ensure-WorkspaceRepo

  $dirty = & git -C $WorkspaceDir status --porcelain 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to read git status for $WorkspaceDir"
  }

  if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String))) {
    Write-WarnLine "$WorkspaceDir has local changes; skipping git pull."
    return
  }

  $currentBranch = & git -C $WorkspaceDir branch --show-current 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($currentBranch | Out-String))) {
    return
  }

  $currentBranch = $currentBranch.Trim()
  $remoteName = & git -C $WorkspaceDir config --get "branch.$currentBranch.remote" 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($remoteName | Out-String))) {
    return
  }

  $mergeRef = & git -C $WorkspaceDir config --get "branch.$currentBranch.merge" 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($mergeRef | Out-String))) {
    return
  }

  $remoteName = $remoteName.Trim()
  $mergeBranch = $mergeRef.Trim() -replace '^refs/heads/', ''
  $upstream = "$remoteName/$mergeBranch"

  & git -C $WorkspaceDir show-ref --verify --quiet "refs/remotes/$upstream" 2>$null
  if ($LASTEXITCODE -ne 0) {
    return
  }

  Write-Host "Updating $WorkspaceDir from $upstream"
  & git -C $WorkspaceDir pull --ff-only
  if ($LASTEXITCODE -ne 0) {
    throw "git pull --ff-only failed for $WorkspaceDir"
  }
}

function Ensure-WorkspaceMiseFile {
  if (-not (Test-Path -LiteralPath $MiseDestination)) {
    throw "Missing workspace mise.toml: $MiseDestination"
  }
}

function Invoke-CodexCompile {
  Require-Apm
  $codexDir = Split-Path -Parent $CodexOutput
  if (-not [string]::IsNullOrWhiteSpace($codexDir)) {
    New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
  }

  Push-Location $WorkspaceDir
  try {
    & apm compile --target codex --output $CodexOutput
    if ($LASTEXITCODE -ne 0) {
      throw "apm compile failed."
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-WorkspaceCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$CommandArgs
  )

  Push-Location $WorkspaceDir
  try {
    & apm @CommandArgs
    if ($LASTEXITCODE -ne 0) {
      throw "apm command failed: $($CommandArgs -join ' ')"
    }
  }
  finally {
    Pop-Location
  }
}

function Test-ApmInstallDiagnosticsFailure {
  param(
    [string[]]$OutputLines
  )

  $joined = ($OutputLines | ForEach-Object { "$_" }) -join "`n"
  return ($joined -match '\[[xX]\]\s+[1-9][0-9]* packages failed:' -or
    $joined -match 'Installed .* with [1-9][0-9]* error\(s\)\.')
}

function Invoke-WorkspaceInstallCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$InstallArgs
  )

  Push-Location $WorkspaceDir
  try {
    $outputLines = @(& apm install @InstallArgs 2>&1)
    foreach ($line in $outputLines) {
      Write-Host $line
    }
    if ($LASTEXITCODE -ne 0) {
      throw "apm install failed: $($InstallArgs -join ' ')"
    }
    if (Test-ApmInstallDiagnosticsFailure -OutputLines $outputLines) {
      throw "apm install reported integration diagnostics: $($InstallArgs -join ' ')"
    }
  }
  finally {
    Pop-Location
  }
}

function Install-WorkspaceMcpDependencies {
  Invoke-WorkspaceInstallCommand -InstallArgs @("-g", "--only", "mcp")
}

function Test-ManifestHasLocalPackages {
  $manifestPath = Join-Path $WorkspaceDir "apm.yml"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    return $false
  }

  $manifestContent = Get-Content -LiteralPath $manifestPath -ErrorAction SilentlyContinue
  return [bool]($manifestContent | Select-String -Pattern '^\s*-\s+\./packages/')
}

function Get-LockPinnedReferenceMap {
  $map = @{}
  foreach ($record in (Get-LockedExternalSkillRecords)) {
    $canonical = if ([string]::IsNullOrWhiteSpace($record.Path)) {
      $record.Repo
    } else {
      "$($record.Repo)/$($record.Path)"
    }

    $map[$canonical] = "$canonical#$($record.Commit)"
  }

  return $map
}

function Get-LockedExternalSkillRecords {
  $lockPath = Join-Path $WorkspaceDir "apm.lock.yaml"
  if (-not (Test-Path -LiteralPath $lockPath)) {
    throw "Lock file not found: $lockPath"
  }

  function Get-YamlIndentLevel {
    param([string]$Line)

    return ($Line.Length - $Line.TrimStart(' ').Length)
  }

  $records = @()
  $current = @{}
  $inDependencies = $false
  $dependenciesIndent = -1
  $currentRecordIndent = -1
  foreach ($line in (Get-Content -LiteralPath $lockPath)) {
    if ($line -match '^(?<indent>\s*)(?<key>[^:#-][^:]*):(?:\s*(?<value>.*))?$') {
      $indentLevel = $Matches['indent'].Length
      $key = $Matches['key'].Trim()

      if ($indentLevel -eq 0) {
        if ($inDependencies -and $current.ContainsKey('repo_url')) {
          $records += [pscustomobject]$current
          $current = @{}
          $currentRecordIndent = -1
        }

        $inDependencies = ($key -eq 'dependencies')
        $dependenciesIndent = if ($inDependencies) { 0 } else { -1 }
        continue
      }

      if ($inDependencies -and $indentLevel -le $dependenciesIndent) {
        if ($current.ContainsKey('repo_url')) {
          $records += [pscustomobject]$current
        }
        $current = @{}
        $currentRecordIndent = -1
        $inDependencies = $false
        $dependenciesIndent = -1
        continue
      }
    }

    if (-not $inDependencies) {
      continue
    }

    if ($line -match '^(?<indent>\s*)-\s+repo_url:\s+(?<repo>.+)$') {
      if ($current.ContainsKey('repo_url')) {
        $records += [pscustomobject]$current
      }
      $current = @{ repo_url = $Matches['repo'].Trim() }
      $currentRecordIndent = $Matches['indent'].Length
      continue
    }

    if (-not $current.ContainsKey('repo_url')) {
      continue
    }

    $indentLevel = Get-YamlIndentLevel -Line $line
    if ($indentLevel -le $currentRecordIndent) {
      continue
    }

    if ($line -match '^\s+resolved_commit:\s+(.+)$') {
      $current.resolved_commit = $Matches[1].Trim()
      continue
    }

    if ($line -match '^\s+virtual_path:\s+(.+)$') {
      $current.virtual_path = $Matches[1].Trim()
      continue
    }
  }

  if ($current.ContainsKey('repo_url')) {
    $records += [pscustomobject]$current
  }

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($record in $records) {
    if (-not $record.PSObject.Properties.Name.Contains('resolved_commit')) {
      continue
    }

    $result.Add([pscustomobject]@{
      Repo = $record.repo_url
      Path = if ($record.PSObject.Properties.Name.Contains('virtual_path') -and -not [string]::IsNullOrWhiteSpace($record.virtual_path)) { $record.virtual_path } else { "" }
      Commit = $record.resolved_commit
    })
  }

  return $result.ToArray()
}

function Format-SkillName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$SourceSkillId
  )

  if ($Target -eq "codex" -and $SourceSkillId.StartsWith("superpowers:")) {
    return ("superpowers-" + $SourceSkillId.Substring("superpowers:".Length))
  }

  return $SourceSkillId
}

function Get-UnpinnedExternalReferences {
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($reference in (Get-ManifestApmDependencyReferences)) {
    if ($reference -notmatch '#') {
      $result.Add($reference)
    }
  }

  return $result.ToArray()
}

function Get-ManifestApmDependencyReferences {
  $manifestPath = Join-Path $WorkspaceDir "apm.yml"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    return @()
  }

  function Get-YamlIndentLevel {
    param([string]$Line)

    return ($Line.Length - $Line.TrimStart(' ').Length)
  }

  $result = New-Object System.Collections.Generic.List[string]
  $inDependencies = $false
  $dependenciesIndent = -1
  $inApm = $false
  $apmIndent = -1
  foreach ($line in (Get-Content -LiteralPath $manifestPath)) {
    if ($line -match '^(?<indent>\s*)(?<key>[^:#][^:]*):(?:\s*(?<value>.*))?$') {
      $indentLevel = $Matches['indent'].Length
      $key = $Matches['key'].Trim()

      if ($indentLevel -eq 0) {
        $inDependencies = ($key -eq 'dependencies')
        $dependenciesIndent = if ($inDependencies) { 0 } else { -1 }
        $inApm = $false
        $apmIndent = -1
        continue
      }

      if ($inDependencies -and $indentLevel -le $dependenciesIndent) {
        $inDependencies = $false
        $dependenciesIndent = -1
        $inApm = $false
        $apmIndent = -1
        continue
      }

      if ($inDependencies) {
        if ($indentLevel -eq ($dependenciesIndent + 2) -and $key -eq 'apm') {
          $inApm = $true
          $apmIndent = $indentLevel
          continue
        }

        if ($inApm -and $indentLevel -le $apmIndent) {
          $inApm = $false
          $apmIndent = -1
        }
      }
    }

    if (-not $inDependencies -or -not $inApm) {
      continue
    }

    if ($line -match '^\s*-\s+(\S+)\s*$') {
      if ((Get-YamlIndentLevel -Line $line) -lt $apmIndent) {
        continue
      }

      $reference = $Matches[1]
      if ($reference -match '^jey3dayo/apm-workspace/catalog(?:#|$)') {
        continue
      }
      if ($reference -match '^\.\/') {
        continue
      }
      if (-not $result.Contains($reference)) {
        $result.Add($reference)
      }
    }
  }

  return $result.ToArray()
}

function Get-ManagedCatalogSkillInventory {
  param(
    [string[]]$SkillIds = @(Get-ManagedSkillIds),
    [object[]]$Targets = @(Get-ManagedCatalogRuntimeTargets)
  )

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($target in $Targets) {
    foreach ($skillId in $SkillIds) {
      $result.Add([pscustomobject]@{
        Target = $target.Name
        SourceSkillId = $skillId
        DeployedSkillName = Format-SkillName -Target $target.Name -SourceSkillId $skillId
      })
    }
  }

  return $result.ToArray()
}

function Get-ManifestReferenceKeys {
  $keys = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($reference in (Get-ManifestApmDependencyReferences)) {
    $null = $keys.Add($reference)
    $baseReference = ($reference -replace '#.*$', '')
    $null = $keys.Add($baseReference)
  }

  return $keys
}

function New-TemporaryDirectory {
  param(
    [string]$Prefix = "apm-temp"
  )

  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("{0}-{1}" -f $Prefix, ([guid]::NewGuid().ToString("N")))
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

function Get-ApmModulesRoot {
  return (Join-Path $WorkspaceDir "apm_modules")
}

function Convert-ReferencePathToSegments {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $segments = @($Value -split '/')
  if (-not $segments -or $segments.Count -eq 0) {
    throw "Invalid dependency path: $Value"
  }

  foreach ($segment in $segments) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @(".", "..")) {
      throw "Invalid dependency path: $Value"
    }

    if ($segment -notmatch '^[A-Za-z0-9._-]+$') {
      throw "Invalid dependency path: $Value"
    }
  }

  return $segments
}

function Test-PathEndsWithSegments {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$PathSegments,

    [Parameter(Mandatory = $true)]
    [string[]]$SuffixSegments
  )

  if ($SuffixSegments.Count -eq 0 -or $PathSegments.Count -lt $SuffixSegments.Count) {
    return $false
  }

  $offset = $PathSegments.Count - $SuffixSegments.Count
  for ($index = 0; $index -lt $SuffixSegments.Count; $index++) {
    if ($PathSegments[$offset + $index] -ne $SuffixSegments[$index]) {
      return $false
    }
  }

  return $true
}

function Get-CanonicalLockRecordReference {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Record
  )

  if ([string]::IsNullOrWhiteSpace($Record.Path)) {
    return $Record.Repo
  }

  return "{0}/{1}" -f $Record.Repo, $Record.Path
}

function Get-ExternalSkillInstallPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoUrl,

    [string]$VirtualPath,

    [string]$ResolvedCommit
  )

  $apmModulesRoot = Get-ApmModulesRoot
  if (-not (Test-Path -LiteralPath $apmModulesRoot)) {
    throw "External skill cache missing: $apmModulesRoot"
  }

  $repoSegments = @(Convert-ReferencePathToSegments -Value $RepoUrl)
  $virtualSegments = if ([string]::IsNullOrWhiteSpace($VirtualPath)) { @() } else { @(Convert-ReferencePathToSegments -Value $VirtualPath) }
  $strippedVirtualPath = if ([string]::IsNullOrWhiteSpace($VirtualPath)) { $null } else { Get-ExternalSkillRelativePath -VirtualPath $VirtualPath }
  $strippedVirtualSegments = if ([string]::IsNullOrWhiteSpace($strippedVirtualPath)) { @() } else { @(Convert-ReferencePathToSegments -Value $strippedVirtualPath) }

  $candidatePaths = New-Object System.Collections.Generic.List[string]
  $seenCandidates = New-Object 'System.Collections.Generic.HashSet[string]'

  function Add-ExternalSkillCandidatePath {
    param(
      [Parameter(Mandatory = $true)]
      [string[]]$Segments
    )

    $candidatePath = $apmModulesRoot
    foreach ($segment in $Segments) {
      $candidatePath = Join-Path $candidatePath $segment
    }

    if ($seenCandidates.Add($candidatePath)) {
      $candidatePaths.Add($candidatePath)
    }
  }

  if ($virtualSegments.Count -gt 0) {
    Add-ExternalSkillCandidatePath -Segments @($repoSegments + $virtualSegments)
    if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit)) {
      Add-ExternalSkillCandidatePath -Segments @($repoSegments + @($ResolvedCommit) + $virtualSegments)
    }
  } else {
    Add-ExternalSkillCandidatePath -Segments $repoSegments
    if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit)) {
      Add-ExternalSkillCandidatePath -Segments @($repoSegments + @($ResolvedCommit))
      Add-ExternalSkillCandidatePath -Segments @(@($ResolvedCommit) + $repoSegments)
    }
  }

  if ($strippedVirtualSegments.Count -gt 0) {
    Add-ExternalSkillCandidatePath -Segments @($repoSegments + $strippedVirtualSegments)
    if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit)) {
      Add-ExternalSkillCandidatePath -Segments @($repoSegments + @($ResolvedCommit) + $strippedVirtualSegments)
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit) -and $virtualSegments.Count -gt 0) {
    Add-ExternalSkillCandidatePath -Segments @(@($ResolvedCommit) + $repoSegments + $virtualSegments)
  }
  if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit) -and $strippedVirtualSegments.Count -gt 0) {
    Add-ExternalSkillCandidatePath -Segments @(@($ResolvedCommit) + $repoSegments + $strippedVirtualSegments)
  }

  $foundPath = $null
  foreach ($candidatePath in $candidatePaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $candidatePath "SKILL.md"))) {
      continue
    }

    if ($null -ne $foundPath -and $foundPath -ne $candidatePath) {
      throw "Ambiguous external skill cache paths for $RepoUrl/$VirtualPath"
    }

    $foundPath = $candidatePath
  }

  if ($null -ne $foundPath) {
    return $foundPath
  }

  if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
    throw "Missing external skill cache for $RepoUrl@$ResolvedCommit"
  }

  $fallbackSuffixes = New-Object System.Collections.Generic.List[object]
  $seenSuffixes = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($suffixSegments in @($virtualSegments, $strippedVirtualSegments)) {
    if (-not $suffixSegments -or $suffixSegments.Count -eq 0) {
      continue
    }

    $suffixKey = ($suffixSegments -join '/')
    if ($seenSuffixes.Add($suffixKey)) {
      $fallbackSuffixes.Add($suffixSegments)
    }
  }

  $resolvedModulesRoot = (Resolve-Path -LiteralPath $apmModulesRoot).Path
  $skillFiles = @(Get-ChildItem -LiteralPath $apmModulesRoot -Recurse -Force -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)
  $matches = New-Object System.Collections.Generic.List[object]
  $seenMatches = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($skillFile in $skillFiles) {
    $candidateDir = Split-Path -Parent $skillFile.FullName
    $candidateRelativePath = $candidateDir.Substring($resolvedModulesRoot.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($candidateRelativePath)) {
      continue
    }

    $candidateRelativeSegments = @($candidateRelativePath -split '[\\/]')
    if (-not ($fallbackSuffixes | Where-Object { Test-PathEndsWithSegments -PathSegments $candidateRelativeSegments -SuffixSegments $_ })) {
      continue
    }

    $normalizedCandidateRelativePath = $candidateRelativeSegments -join '/'
    if (-not $seenMatches.Add($candidateDir)) {
      continue
    }

    $score = 0
    if ($normalizedCandidateRelativePath.Contains($RepoUrl)) {
      $score += 10
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit) -and $normalizedCandidateRelativePath.Contains($ResolvedCommit)) {
      $score += 1
    }

    $matches.Add([pscustomobject]@{
        Score = $score
        Path = $candidateDir
      })
  }

  if ($matches.Count -eq 0) {
    throw "Missing external skill cache for $RepoUrl/$VirtualPath@$ResolvedCommit"
  }

  $bestMatches = @($matches | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Path'; Descending = $false })
  if ($bestMatches.Count -gt 1 -and $bestMatches[0].Score -eq $bestMatches[1].Score) {
    throw "Ambiguous external skill cache for $RepoUrl/$VirtualPath@$ResolvedCommit"
  }

  return $bestMatches[0].Path
}

function Get-ExternalPackageSkillsRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoUrl,

    [string]$VirtualPath,

    [string]$ResolvedCommit
  )

  if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
    return $null
  }

  $apmModulesRoot = Get-ApmModulesRoot
  if (-not (Test-Path -LiteralPath $apmModulesRoot)) {
    return $null
  }

  $repoSegments = @(Convert-ReferencePathToSegments -Value $RepoUrl)
  $virtualSegments = @(Convert-ReferencePathToSegments -Value $VirtualPath)
  $candidatePaths = New-Object System.Collections.Generic.List[string]
  $seenCandidates = New-Object 'System.Collections.Generic.HashSet[string]'

  function Add-ExternalPackageCandidatePath {
    param(
      [Parameter(Mandatory = $true)]
      [string[]]$Segments
    )

    $candidatePath = $apmModulesRoot
    foreach ($segment in $Segments) {
      $candidatePath = Join-Path $candidatePath $segment
    }

    if ($seenCandidates.Add($candidatePath)) {
      $candidatePaths.Add($candidatePath)
    }
  }

  Add-ExternalPackageCandidatePath -Segments @($repoSegments + $virtualSegments)
  if (-not [string]::IsNullOrWhiteSpace($ResolvedCommit)) {
    Add-ExternalPackageCandidatePath -Segments @($repoSegments + @($ResolvedCommit) + $virtualSegments)
    Add-ExternalPackageCandidatePath -Segments @(@($ResolvedCommit) + $repoSegments + $virtualSegments)
  }

  $foundPath = $null
  foreach ($candidatePath in $candidatePaths) {
    $skillsRoot = Join-Path $candidatePath ".apm/skills"
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) {
      continue
    }

    if ($null -ne $foundPath -and $foundPath -ne $skillsRoot) {
      throw "Ambiguous external package cache paths for $RepoUrl/$VirtualPath"
    }

    $foundPath = $skillsRoot
  }

  return $foundPath
}

function Get-ExternalSkillId {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoUrl,

    [string]$VirtualPath
  )

  if ($RepoUrl -eq "obra/superpowers" -and -not [string]::IsNullOrWhiteSpace($VirtualPath)) {
    $relativePath = Get-ExternalSkillRelativePath -VirtualPath $VirtualPath
    $skillId = ((Convert-ReferencePathToSegments -Value $relativePath) -join ':')
    Test-SkillId -SkillId $skillId
    return ("superpowers:{0}" -f $skillId)
  }

  if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
    $segments = Convert-ReferencePathToSegments -Value $RepoUrl
    $skillId = $segments[-1]
    Test-SkillId -SkillId $skillId
    return $skillId
  }

  $relativePath = Get-ExternalSkillRelativePath -VirtualPath $VirtualPath
  $skillId = ((Convert-ReferencePathToSegments -Value $relativePath) -join ':')
  Test-SkillId -SkillId $skillId
  return $skillId
}

function Get-PersonalSkillRecords {
  $result = New-Object System.Collections.Generic.List[object]
  foreach ($skillId in (Get-ManagedSkillIds)) {
    $result.Add([pscustomobject]@{
        SourceKind = "personal"
        SourceSkillId = $skillId
        SourcePath = Get-ManagedSkillContentDir -SkillId $skillId
      })
  }

  return $result.ToArray()
}

function Get-ExternalSkillRecords {
  $manifestReferences = @(Get-ManifestApmDependencyReferences)
  $lockRecords = @(Get-LockedExternalSkillRecords)
  if ($manifestReferences.Count -eq 0 -and $lockRecords.Count -eq 0) {
    return @()
  }

  $manifestReferenceKeys = Get-ManifestReferenceKeys
  $matchedReferences = New-Object 'System.Collections.Generic.HashSet[string]'
  $seenCanonical = New-Object 'System.Collections.Generic.HashSet[string]'
  $result = New-Object System.Collections.Generic.List[object]

  foreach ($record in $lockRecords) {
    $canonicalReference = Get-CanonicalLockRecordReference -Record $record
    if ($canonicalReference -eq 'jey3dayo/apm-workspace/catalog') {
      continue
    }
    if (-not $manifestReferenceKeys.Contains($canonicalReference)) {
      throw "External lock record is not declared in apm.yml: $canonicalReference"
    }

    $null = $matchedReferences.Add($canonicalReference)
    if (-not [string]::IsNullOrWhiteSpace($record.Commit)) {
      $null = $matchedReferences.Add(("{0}#{1}" -f $canonicalReference, $record.Commit))
    }
    if (-not $seenCanonical.Add($canonicalReference)) {
      continue
    }

    $packageSkillsRoot = Get-ExternalPackageSkillsRoot -RepoUrl $record.Repo -VirtualPath $record.Path -ResolvedCommit $record.Commit
    if ($null -ne $packageSkillsRoot) {
      foreach ($skillId in (Get-SkillIdsFromRoot -SkillsRoot $packageSkillsRoot)) {
        $sourcePath = $packageSkillsRoot
        foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $skillId)) {
          $sourcePath = Join-Path $sourcePath $segment
        }

        $result.Add([pscustomobject]@{
            SourceKind = "external"
            SourceSkillId = $skillId
            SourcePath = $sourcePath
            CanonicalReference = ("{0}#{1}" -f $canonicalReference, $skillId)
          })
      }
      continue
    }

    $sourcePath = Get-ExternalSkillInstallPath -RepoUrl $record.Repo -VirtualPath $record.Path -ResolvedCommit $record.Commit
    if (-not (Test-Path -LiteralPath $sourcePath)) {
      throw "External dependency is not available in local apm_modules: $canonicalReference ($sourcePath). Run 'mise run refresh' first."
    }

    $skillFile = Join-Path $sourcePath "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile)) {
      continue
    }

    $result.Add([pscustomobject]@{
        SourceKind = "external"
        SourceSkillId = Get-ExternalSkillId -RepoUrl $record.Repo -VirtualPath $record.Path
        SourcePath = $sourcePath
        CanonicalReference = $canonicalReference
      })
  }

  foreach ($reference in $manifestReferences) {
    if (-not $matchedReferences.Contains($reference)) {
      throw "Manifest dependency is missing from apm.lock.yaml: $reference"
    }
  }

  return $result.ToArray()
}

function Build-DeploymentPlanEntries {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$SkillRecords,

    [object[]]$Targets = @(Get-ManagedCatalogRuntimeTargets)
  )

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($target in $Targets) {
    foreach ($skillRecord in $SkillRecords) {
      $result.Add([pscustomobject]@{
          Target = $target.Name
          TargetRoot = $target.Root
          SourceKind = $skillRecord.SourceKind
          SourceSkillId = $skillRecord.SourceSkillId
          SourcePath = $skillRecord.SourcePath
          DeployedSkillName = Format-SkillName -Target $target.Name -SourceSkillId $skillRecord.SourceSkillId
        })
    }
  }

  return $result.ToArray()
}

function Validate-DeploymentCollisions {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$SkillRecords,

    [object[]]$Targets = @(Get-ManagedCatalogRuntimeTargets)
  )

  $sourceOwners = @{}
  foreach ($skillRecord in $SkillRecords) {
    if ($sourceOwners.ContainsKey($skillRecord.SourceSkillId)) {
      $existing = $sourceOwners[$skillRecord.SourceSkillId]
      throw "Duplicate source skill id '$($skillRecord.SourceSkillId)' from $($existing.SourceKind) ($($existing.SourcePath)) and $($skillRecord.SourceKind) ($($skillRecord.SourcePath))."
    }

    $sourceOwners[$skillRecord.SourceSkillId] = $skillRecord
  }

  $plannedNames = @{}
  foreach ($entry in (Build-DeploymentPlanEntries -SkillRecords $SkillRecords -Targets $Targets)) {
    $collisionKey = "{0}|{1}" -f $entry.Target, $entry.DeployedSkillName
    if ($plannedNames.ContainsKey($collisionKey)) {
      $existing = $plannedNames[$collisionKey]
      throw "Deployment collision for target '$($entry.Target)': '$($existing.SourceSkillId)' and '$($entry.SourceSkillId)' both deploy as '$($entry.DeployedSkillName)'."
    }

    $plannedNames[$collisionKey] = $entry
  }
}

function Get-StagedTargetSkillsRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,

    [Parameter(Mandatory = $true)]
    [string]$TargetName
  )

  return (Join-Path (Join-Path $StageRoot $TargetName) "skills")
}

function Get-StagedSkillDestinationPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,

    [Parameter(Mandatory = $true)]
    [string]$TargetName,

    [Parameter(Mandatory = $true)]
    [string]$DeployedSkillName
  )

  $destination = Get-StagedTargetSkillsRoot -StageRoot $StageRoot -TargetName $TargetName
  foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $DeployedSkillName)) {
    $destination = Join-Path $destination $segment
  }

  return $destination
}

function Stage-TargetSkillRecords {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,

    [Parameter(Mandatory = $true)]
    [object[]]$SkillRecords,

    [object[]]$Targets = @(Get-ManagedCatalogRuntimeTargets)
  )

  New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
  foreach ($target in $Targets) {
    New-Item -ItemType Directory -Path (Get-StagedTargetSkillsRoot -StageRoot $StageRoot -TargetName $target.Name) -Force | Out-Null
  }

  $planEntries = @(Build-DeploymentPlanEntries -SkillRecords $SkillRecords -Targets $Targets)
  foreach ($entry in $planEntries) {
    $destinationPath = Get-StagedSkillDestinationPath -StageRoot $StageRoot -TargetName $entry.Target -DeployedSkillName $entry.DeployedSkillName
    Copy-DirectoryContents -SourceDir $entry.SourcePath -DestinationDir $destinationPath
  }

  return $planEntries
}

function Build-TargetSkillTrees {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,

    [object[]]$Targets = @(Get-ManagedCatalogRuntimeTargets)
  )

  $personalSkillRecords = @(Get-PersonalSkillRecords)
  $externalSkillRecords = @(Get-ExternalSkillRecords)
  $skillRecords = @($personalSkillRecords + $externalSkillRecords)

  Validate-DeploymentCollisions -SkillRecords $skillRecords -Targets $Targets
  return @(Stage-TargetSkillRecords -StageRoot $StageRoot -SkillRecords $skillRecords -Targets $Targets)
}

function Replace-SkillTargetsFromStage {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,

    [object[]]$Targets = @(Get-ManagedCatalogRuntimeTargets)
  )

  foreach ($target in $Targets) {
    New-Item -ItemType Directory -Path $target.Root -Force | Out-Null

    $stagedSkillsRoot = Get-StagedTargetSkillsRoot -StageRoot $StageRoot -TargetName $target.Name
    if (-not (Test-Path -LiteralPath $stagedSkillsRoot)) {
      New-Item -ItemType Directory -Path $stagedSkillsRoot -Force | Out-Null
    }

    $skillsRoot = if ($target.PSObject.Properties.Name -contains "SkillsRoot" -and $target.SkillsRoot) { $target.SkillsRoot } else { $target.Root }
    New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
    $legacySkillsRoot = Join-Path $target.Root "skills"
    $destinationSkillsRoot = Join-Path $skillsRoot "skills"
    $backupSkillsRoot = Join-Path $target.Root (".skills.apm-backup-{0}" -f ([guid]::NewGuid().ToString("N")))

    if (($legacySkillsRoot -ne $destinationSkillsRoot) -and (Test-Path -LiteralPath $legacySkillsRoot)) {
      Remove-Item -LiteralPath $legacySkillsRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $backupSkillsRoot) {
      Remove-Item -LiteralPath $backupSkillsRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $destinationSkillsRoot) {
      Move-Item -LiteralPath $destinationSkillsRoot -Destination $backupSkillsRoot
    }

    try {
      Move-Item -LiteralPath $stagedSkillsRoot -Destination $destinationSkillsRoot
    }
    catch {
      if ((-not (Test-Path -LiteralPath $destinationSkillsRoot)) -and (Test-Path -LiteralPath $backupSkillsRoot)) {
        Move-Item -LiteralPath $backupSkillsRoot -Destination $destinationSkillsRoot
      }
      throw
    }
    finally {
      if (Test-Path -LiteralPath $backupSkillsRoot) {
        Remove-Item -LiteralPath $backupSkillsRoot -Recurse -Force
      }
    }
  }
}

function Invoke-PinExternal {
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold

  $manifestPath = Join-Path $WorkspaceDir "apm.yml"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
  }

  $pinMap = Get-LockPinnedReferenceMap
  $updatedCount = 0
  $updatedLines = New-Object System.Collections.Generic.List[string]

  foreach ($line in (Get-Content -LiteralPath $manifestPath)) {
    if ($line -match '^(\s*-\s+)(\S+)\s*$') {
      $prefix = $Matches[1]
      $reference = $Matches[2]
      if ($reference -notmatch '#' -and $pinMap.ContainsKey($reference)) {
        $updatedLines.Add("$prefix$($pinMap[$reference])")
        $updatedCount += 1
        continue
      }
    }

    $updatedLines.Add($line)
  }

  if ($updatedCount -eq 0) {
    Write-Host "No external dependencies needed pinning."
    return
  }

  $content = (($updatedLines.ToArray()) -join "`r`n") + "`r`n"
  [System.IO.File]::WriteAllText($manifestPath, $content)
  Write-SuccessLine ("Pinned {0} external dependency references in apm.yml" -f $updatedCount)
}

function Invoke-Apply {
  Require-Apm
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Invoke-ValidateCatalog
  Ensure-WorkspaceMiseFile

  if (Test-ManifestHasLocalPackages) {
    throw "apm 0.8.11 cannot deploy ./packages/* dependencies at user scope yet. Remove local package refs from ~/.apm/apm.yml and keep the global manifest on upstream refs such as jey3dayo/apm-workspace/catalog#main."
  }

  $stageDir = New-TemporaryDirectory -Prefix "apm-apply"
  try {
    $null = Build-TargetSkillTrees -StageRoot $stageDir
    Sync-ManagedCatalogRuntimeAssets
    Replace-SkillTargetsFromStage -StageRoot $stageDir
    Install-WorkspaceMcpDependencies
  }
  finally {
    if (Test-Path -LiteralPath $stageDir) {
      Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Invoke-CodexCompile
}

function Get-RequestedPersonalSkillRecords {
  param(
    [string[]]$RequestedSkillIds
  )

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($skillId in (Get-RequestedLocalSkillIds -RequestedSkillIds $RequestedSkillIds)) {
    $result.Add([pscustomobject]@{
        SourceKind = "personal"
        SourceSkillId = $skillId
        SourcePath = Get-LocalSkillContentDir -SkillId $skillId
      })
  }

  return $result.ToArray()
}

function Get-LocalCodexSyncTarget {
  return [pscustomobject]@{
    Name = "codex"
    Root = (Join-Path $HOME ".codex")
    SkillsRoot = (Join-Path $HOME ".agents")
    ConfigName = "AGENTS.md"
  }
}

function Invoke-SyncLocalSkills {
  param(
    [string[]]$RequestedSkillIds
  )

  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold

  $targets = @(Get-LocalCodexSyncTarget)
  $stageDir = New-TemporaryDirectory -Prefix "apm-sync-local"

  try {
    $skillRecords = @(Get-RequestedPersonalSkillRecords -RequestedSkillIds $RequestedSkillIds)
    Validate-DeploymentCollisions -SkillRecords $skillRecords -Targets $targets
    $null = Stage-TargetSkillRecords -StageRoot $stageDir -SkillRecords $skillRecords -Targets $targets
    $target = $targets[0]
    $stagedSkillsRoot = Get-StagedTargetSkillsRoot -StageRoot $stageDir -TargetName $target.Name
    $destinationSkillsRoot = Join-Path $target.SkillsRoot "skills"

    New-Item -ItemType Directory -Path $destinationSkillsRoot -Force | Out-Null

    foreach ($skillRecord in $skillRecords) {
      $deployedSkillName = Format-SkillName -Target $target.Name -SourceSkillId $skillRecord.SourceSkillId
      $stagedSkillPath = Get-InternalTargetSkillPath -TargetRoot $stagedSkillsRoot -SkillId $deployedSkillName
      $destinationSkillPath = Get-InternalTargetSkillPath -TargetRoot $destinationSkillsRoot -SkillId $deployedSkillName
      Copy-DirectoryContents -SourceDir $stagedSkillPath -DestinationDir $destinationSkillPath
    }
  }
  finally {
    if (Test-Path -LiteralPath $stageDir) {
      Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Host ("Synced local catalog/private skills to Codex target: {0}" -f ((@($skillRecords | ForEach-Object SourceSkillId)) -join ", "))
}

function Invoke-Update {
  Require-Apm
  Ensure-WorkspaceRepo
  Refresh-WorkspaceCheckout
  Ensure-WorkspaceScaffold
  Invoke-ValidateCatalog

  if (Test-ManifestHasLocalPackages) {
    throw "apm 0.8.11 cannot update ./packages/* dependencies at user scope yet. Refresh stopped before deps update; remove local package refs from ~/.apm/apm.yml first."
  }

  & apm deps update -g
  if ($LASTEXITCODE -ne 0) {
    throw "apm deps update -g failed."
  }
}

function Get-CatalogBuildDir {
  return (Join-Path $CatalogBuildRootDir $CatalogDirName)
}

function Invoke-Validate {
  Require-Apm
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Invoke-WorkspaceCommand -CommandArgs @("compile", "--validate")
}

function Get-CatalogBuildSkillsRoot {
  return (Join-Path (Get-CatalogBuildDir) ".apm\skills")
}

function Get-CatalogBuildAgentsRoot {
  return (Join-Path (Get-CatalogBuildDir) "agents")
}

function Get-CatalogBuildCommandsRoot {
  return (Join-Path (Get-CatalogBuildDir) "commands")
}

function Get-CatalogBuildRulesRoot {
  return (Join-Path (Get-CatalogBuildDir) "rules")
}

function Get-CatalogBuildInstructionsPath {
  return (Join-Path (Get-CatalogBuildDir) "AGENTS.md")
}

function Get-TrackedCatalogDir {
  return (Join-Path $WorkspaceDir $CatalogDirName)
}

function Get-TrackedCatalogSkillsRoot {
  return (Join-Path $WorkspaceDir "catalog\skills")
}

function Get-PrivateSkillsRoot {
  return (Join-Path $WorkspaceDir "private-skills\.apm\skills")
}

function Get-TrackedCatalogAgentsRoot {
  return (Join-Path (Get-TrackedCatalogDir) "agents")
}

function Get-TrackedCatalogCommandsRoot {
  return (Join-Path (Get-TrackedCatalogDir) "commands")
}

function Get-TrackedCatalogRulesRoot {
  return (Join-Path (Get-TrackedCatalogDir) "rules")
}

function Get-TrackedCatalogInstructionsPath {
  return (Join-Path (Get-TrackedCatalogDir) "AGENTS.md")
}

function Get-TrackedCatalogRelativePath {
  return $CatalogDirName
}

function Get-SkillIdsFromRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillsRoot
  )

  if (-not (Test-Path -LiteralPath $SkillsRoot)) {
    return @()
  }

  $result = New-Object System.Collections.Generic.List[string]
  foreach ($skillFile in (Get-ChildItem -LiteralPath $SkillsRoot -Recurse -Filter "SKILL.md" -File | Sort-Object FullName)) {
    $skillDir = Split-Path -Parent $skillFile.FullName
    $relativePath = $skillDir.Substring($SkillsRoot.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
      continue
    }

    $skillId = ($relativePath -replace '[\\/]', ':')
    if (-not $result.Contains($skillId)) {
      $result.Add($skillId)
    }
  }

  return $result.ToArray()
}

function Get-ManagedSkillIds {
  return @(Get-SkillIdsFromRoot -SkillsRoot (Get-TrackedCatalogSkillsRoot))
}

function Get-PrivateSkillIds {
  return @(Get-SkillIdsFromRoot -SkillsRoot (Get-PrivateSkillsRoot))
}

function Get-LocalSkillIds {
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($skillId in (@(Get-PrivateSkillIds) + @(Get-ManagedSkillIds))) {
    if (-not [string]::IsNullOrWhiteSpace($skillId) -and -not $result.Contains($skillId)) {
      $result.Add($skillId)
    }
  }

  return $result.ToArray()
}

function Get-RequestedManagedSkillIds {
  param(
    [string[]]$RequestedSkillIds
  )

  if ($RequestedSkillIds -and $RequestedSkillIds.Count -gt 0) {
    foreach ($skillId in $RequestedSkillIds) {
      Test-SkillId -SkillId $skillId
    }
    return $RequestedSkillIds
  }

  return @(Get-ManagedSkillIds)
}

function Get-RequestedCatalogSkillIds {
  param(
    [string[]]$RequestedSkillIds
  )

  $trackedSkillIds = @(Get-TrackedCatalogSkillIds)
  if ($RequestedSkillIds -and $RequestedSkillIds.Count -gt 0) {
    foreach ($skillId in $RequestedSkillIds) {
      Test-SkillId -SkillId $skillId
      if ($skillId -notin $trackedSkillIds) {
        throw "Requested catalog skill is not tracked in catalog/skills: $skillId"
      }
    }
    return $RequestedSkillIds
  }

  return $trackedSkillIds
}

function Get-RequestedLocalSkillIds {
  param(
    [string[]]$RequestedSkillIds
  )

  $availableSkillIds = @(Get-LocalSkillIds)
  if ($RequestedSkillIds -and $RequestedSkillIds.Count -gt 0) {
    foreach ($skillId in $RequestedSkillIds) {
      Test-SkillId -SkillId $skillId
      if ($skillId -notin $availableSkillIds) {
        throw "Requested local skill is not available in catalog/skills or private-skills: $skillId"
      }
    }
    return $RequestedSkillIds
  }

  return $availableSkillIds
}

function Get-TrackedCatalogAgentRelativePaths {
  return @(Get-RelativeFilePaths -RootDir (Get-TrackedCatalogAgentsRoot))
}

function Get-ManagedAgentRelativePaths {
  return @(Get-TrackedCatalogAgentRelativePaths)
}

function Get-TrackedCatalogCommandRelativePaths {
  return @(Get-RelativeFilePaths -RootDir (Get-TrackedCatalogCommandsRoot))
}

function Get-ManagedCommandRelativePaths {
  return @(Get-TrackedCatalogCommandRelativePaths)
}

function Get-TrackedCatalogRuleRelativePaths {
  return @(Get-RelativeFilePaths -RootDir (Get-TrackedCatalogRulesRoot))
}

function Get-ManagedRuleRelativePaths {
  return @(Get-TrackedCatalogRuleRelativePaths)
}

function Test-FileContentEqual {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedPath,

    [Parameter(Mandatory = $true)]
    [string]$ActualPath
  )

  if ((-not (Test-Path -LiteralPath $ExpectedPath)) -or (-not (Test-Path -LiteralPath $ActualPath))) {
    return $false
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $expectedStream = [System.IO.File]::OpenRead($ExpectedPath)
    try {
      $expectedHash = [System.BitConverter]::ToString($sha.ComputeHash($expectedStream)).Replace("-", "")
    }
    finally {
      $expectedStream.Dispose()
    }

    $actualStream = [System.IO.File]::OpenRead($ActualPath)
    try {
      $actualHash = [System.BitConverter]::ToString($sha.ComputeHash($actualStream)).Replace("-", "")
    }
    finally {
      $actualStream.Dispose()
    }
  }
  finally {
    $sha.Dispose()
  }

  return $expectedHash -eq $actualHash
}

function Test-DirectoryTreeEqual {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedRoot,

    [Parameter(Mandatory = $true)]
    [string]$ActualRoot
  )

  if ((-not (Test-Path -LiteralPath $ExpectedRoot)) -or (-not (Test-Path -LiteralPath $ActualRoot))) {
    return $false
  }

  $expectedPaths = @(Get-RelativeFilePaths -RootDir $ExpectedRoot)
  $actualPaths = @(Get-RelativeFilePaths -RootDir $ActualRoot)
  if ((@($expectedPaths) -join "`n") -ne (@($actualPaths) -join "`n")) {
    return $false
  }

  foreach ($relativePath in $expectedPaths) {
    $expectedPath = Join-Path $ExpectedRoot ($relativePath -replace '/', '\')
    $actualPath = Join-Path $ActualRoot ($relativePath -replace '/', '\')
    if (-not (Test-FileContentEqual -ExpectedPath $expectedPath -ActualPath $actualPath)) {
      return $false
    }
  }

  return $true
}

function Get-TrackedCatalogSkillIds {
  return @(Get-SkillIdsFromRoot -SkillsRoot (Get-TrackedCatalogSkillsRoot))
}

function Test-ManifestHasCatalogReference {
  $manifestPath = Join-Path $WorkspaceDir "apm.yml"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    return $false
  }

  $repoReference = Convert-WorkspaceRemoteToRepoReference -RemoteUrl $WorkspaceRepo
  $pattern = [regex]::Escape("$repoReference/$CatalogDirName#")
  return [bool](Get-Content -LiteralPath $manifestPath -ErrorAction SilentlyContinue | Select-String -Pattern $pattern)
}

function Write-CatalogSummary {
  $sourceSkillIds = @(Get-TrackedCatalogSkillIds)
  $sourceAgentPaths = @(Get-ManagedAgentRelativePaths)
  $sourceCommandPaths = @(Get-ManagedCommandRelativePaths)
  $sourceRulePaths = @(Get-ManagedRuleRelativePaths)
  $trackedInstructionsPath = Get-TrackedCatalogInstructionsPath
  $trackedInstructionsPresent = Test-Path -LiteralPath $trackedInstructionsPath
  $trackedManifest = Join-Path (Get-TrackedCatalogDir) "apm.yml"
  $trackedState = if (Test-Path -LiteralPath $trackedManifest) { "yes" } else { "no" }
  $manifestState = if (Test-ManifestHasCatalogReference) { "yes" } else { "no" }
  $instructionsState = if ($trackedInstructionsPresent) { "present" } else { "missing" }
  $coverageState = if (($trackedState -eq "yes") -and ($manifestState -eq "yes") -and ($instructionsState -eq "present")) { "ok" } else { "drift" }

  Write-Host ("catalog: skills={0} agents={1} commands={2} rules={3} instructions={4} tracked-manifest={5} global-ref={6} status={7}" -f $sourceSkillIds.Count, $sourceAgentPaths.Count, $sourceCommandPaths.Count, $sourceRulePaths.Count, $instructionsState, $trackedState, $manifestState, $coverageState)
}


function Get-ManagedCatalogRuntimeTargets {
  return @(
    [pscustomobject]@{ Name = "claude"; Root = (Join-Path $HOME ".claude"); SkillsRoot = (Join-Path $HOME ".claude"); ConfigName = "CLAUDE.md" },
    [pscustomobject]@{ Name = "codex"; Root = (Join-Path $HOME ".codex"); SkillsRoot = (Join-Path $HOME ".agents"); ConfigName = "AGENTS.md" },
    [pscustomobject]@{ Name = "cursor"; Root = (Join-Path $HOME ".cursor"); SkillsRoot = (Join-Path $HOME ".cursor"); ConfigName = "AGENTS.md" },
    [pscustomobject]@{ Name = "opencode"; Root = (Join-Path $HOME ".opencode"); SkillsRoot = (Join-Path $HOME ".opencode"); ConfigName = "CLAUDE.md" },
    [pscustomobject]@{ Name = "openclaw"; Root = (Join-Path $HOME ".openclaw"); SkillsRoot = (Join-Path $HOME ".openclaw"); ConfigName = "CLAUDE.md" }
  )
}

function Copy-ManagedCatalogFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  $destinationDir = Split-Path -Parent $DestinationPath
  if (-not [string]::IsNullOrWhiteSpace($destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Sync-ManagedCatalogRuntimeAssets {
  $trackedDir = Get-TrackedCatalogDir
  if (-not (Test-Path -LiteralPath $trackedDir)) {
    throw "Tracked catalog missing: $trackedDir. Run 'mise run prepare:catalog' first."
  }

  $instructionsSource = Get-TrackedCatalogInstructionsPath
  $agentsSource = Get-TrackedCatalogAgentsRoot
  $commandsSource = Get-TrackedCatalogCommandsRoot
  $rulesSource = Get-TrackedCatalogRulesRoot

  foreach ($target in (Get-ManagedCatalogRuntimeTargets)) {
    New-Item -ItemType Directory -Path $target.Root -Force | Out-Null

    if (Test-Path -LiteralPath $instructionsSource) {
      Copy-ManagedCatalogFile -SourcePath $instructionsSource -DestinationPath (Join-Path $target.Root $target.ConfigName)
    }

    if (Test-Path -LiteralPath $agentsSource) {
      Copy-DirectoryContents -SourceDir $agentsSource -DestinationDir (Join-Path $target.Root "agents")
    }

    if (Test-Path -LiteralPath $commandsSource) {
      Copy-DirectoryContents -SourceDir $commandsSource -DestinationDir (Join-Path $target.Root "commands")
    }

    if (Test-Path -LiteralPath $rulesSource) {
      Copy-DirectoryContents -SourceDir $rulesSource -DestinationDir (Join-Path $target.Root "rules")
    }
  }
}

function Invoke-ValidateCatalog {
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold

  $hasFailure = $false
  $sourceSkillIds = @(Get-TrackedCatalogSkillIds)
  $sourceAgentPaths = @(Get-ManagedAgentRelativePaths)
  $sourceCommandPaths = @(Get-ManagedCommandRelativePaths)
  $sourceRulePaths = @(Get-ManagedRuleRelativePaths)
  $trackedInstructionsPath = Get-TrackedCatalogInstructionsPath
  $trackedManifest = Join-Path (Get-TrackedCatalogDir) "apm.yml"
  $trackedReadme = Join-Path (Get-TrackedCatalogDir) "README.md"

  if (-not (Test-Path -LiteralPath $trackedManifest)) {
    Write-ErrorLine ("Tracked catalog manifest is missing: {0}" -f $trackedManifest)
    $hasFailure = $true
  }

  if (-not (Test-Path -LiteralPath $trackedReadme)) {
    Write-ErrorLine ("Tracked catalog README is missing: {0}" -f $trackedReadme)
    $hasFailure = $true
  }

  if (-not (Test-ManifestHasCatalogReference)) {
    Write-ErrorLine "Global apm.yml is missing the managed catalog ref"
    $hasFailure = $true
  }

  if (-not (Test-Path -LiteralPath $trackedInstructionsPath)) {
    Write-ErrorLine ("Tracked catalog is missing instructions: {0}" -f $trackedInstructionsPath)
    $hasFailure = $true
  }

  foreach ($rootCheck in @(
      @{ Label = "skills"; Path = (Get-TrackedCatalogSkillsRoot) },
      @{ Label = "agents"; Path = (Get-TrackedCatalogAgentsRoot) },
      @{ Label = "commands"; Path = (Get-TrackedCatalogCommandsRoot) },
      @{ Label = "rules"; Path = (Get-TrackedCatalogRulesRoot) }
    )) {
    if (-not (Test-Path -LiteralPath $rootCheck.Path)) {
      Write-ErrorLine ("Tracked catalog is missing {0}: {1}" -f $rootCheck.Label, $rootCheck.Path)
      $hasFailure = $true
    }
  }

  if ($sourceSkillIds.Count -eq 0) {
    Write-ErrorLine "Tracked catalog has no managed skills"
    $hasFailure = $true
  }

  if ($hasFailure) {
    throw "Catalog validation failed"
  }

  Write-SuccessLine ("Catalog validation passed ({0} skills, {1} agents, {2} commands, {3} rules)" -f $sourceSkillIds.Count, $sourceAgentPaths.Count, $sourceCommandPaths.Count, $sourceRulePaths.Count)
}

function Invoke-Doctor {
  Require-Apm
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold

  $manifestState = if (Test-Path (Join-Path $WorkspaceDir "apm.yml")) { "present" } else { "missing" }
  Write-Host ("apm: {0}" -f (apm --version))
  Write-Host ("workspace: {0}" -f $WorkspaceDir)
  Write-Host ("manifest: {0}" -f $manifestState)
  $branch = & git -C $WorkspaceDir branch --show-current 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($branch | Out-String))) {
    $branch = "detached"
  }
  Write-Host ("branch: {0}" -f ($branch | Out-String).Trim())
  Write-Host "remote:"
  & git -C $WorkspaceDir remote -v
  Write-Host "targets:"
  $skillInventory = @(Get-ManagedCatalogSkillInventory)
  $codexMcpConfigPath = Join-Path (Join-Path $HOME ".codex") "config.toml"
  foreach ($target in (Get-ManagedCatalogRuntimeTargets)) {
    $skillsRoot = if ($target.PSObject.Properties.Name -contains "SkillsRoot" -and $target.SkillsRoot) { $target.SkillsRoot } else { $target.Root }
    $skillsPath = Join-Path $skillsRoot "skills"
    $configPath = Join-Path $target.Root $target.ConfigName
    $agentsPath = Join-Path $target.Root "agents"
    $commandsPath = Join-Path $target.Root "commands"
    $rulesPath = Join-Path $target.Root "rules"
    Write-Host ("  {0}: config={1} agents={2} commands={3} rules={4} skills={5}" -f $target.Name, $(if (Test-Path $configPath) { "present" } else { "missing" }), $(if (Test-Path $agentsPath) { "present" } else { "missing" }), $(if (Test-Path $commandsPath) { "present" } else { "missing" }), $(if (Test-Path $rulesPath) { "present" } else { "missing" }), $(if (Test-Path $skillsPath) { "present" } else { "missing" }))
  }
  Write-Host ("codex mcp config: {0}" -f $(if (Test-Path $codexMcpConfigPath) { "present" } else { "missing" }))
  Write-Host ("target skill inventory: entries={0}" -f $skillInventory.Count)
  Write-Host ("external pins: unpinned={0}" -f (@(Get-UnpinnedExternalReferences)).Count)
  Write-CatalogSummary
  & apm deps list -g
  if ($LASTEXITCODE -ne 0) {
    throw "apm deps list -g failed."
  }
}

function Get-InternalDeployTargetRoots {
  return @(
    (Join-Path $HOME ".claude\skills"),
    (Join-Path $HOME ".cursor\skills"),
    (Join-Path $HOME ".opencode\skills"),
    (Join-Path $HOME ".copilot\skills")
  )
}

function Get-InternalTargetSkillPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TargetRoot,
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  $path = $TargetRoot
  foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $SkillId)) {
    $path = Join-Path $path $segment
  }
  return $path
}

function Get-LegacyInternalCleanupAlias {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  if ($SkillId -in @(
      "brainstorming",
      "dispatching-parallel-agents",
      "executing-plans",
      "finishing-a-development-branch",
      "receiving-code-review",
      "requesting-code-review",
      "subagent-driven-development",
      "systematic-debugging",
      "test-driven-development",
      "using-git-worktrees",
      "using-superpowers",
      "verification-before-completion",
      "writing-plans",
      "writing-skills"
    )) {
    return "superpowers:$SkillId"
  }

  return $null
}

function Get-InternalCleanupSkillIds {
  $result = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'

  foreach ($skillId in (Get-ManagedSkillIds)) {
    if ($seen.Add($skillId)) {
      $result.Add($skillId)
    }

    $legacyAlias = Get-LegacyInternalCleanupAlias -SkillId $skillId
    if (-not [string]::IsNullOrWhiteSpace($legacyAlias) -and $seen.Add($legacyAlias)) {
      $result.Add($legacyAlias)
    }
  }

  return $result.ToArray()
}

function Remove-InternalTargetReparsePoints {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$SkillIds
  )

  foreach ($targetRoot in (Get-InternalDeployTargetRoots)) {
    if (-not (Test-Path -LiteralPath $targetRoot)) {
      continue
    }

    foreach ($skillId in $SkillIds) {
      $candidatePaths = @(
        (Join-Path $targetRoot $skillId),
        (Get-InternalTargetSkillPath -TargetRoot $targetRoot -SkillId $skillId)
      ) | Select-Object -Unique

      foreach ($targetPath in $candidatePaths) {
        if (-not (Test-Path -LiteralPath $targetPath)) {
          continue
        }

        $item = Get-Item -LiteralPath $targetPath -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
          try {
            Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
          }
          catch {
            [System.IO.Directory]::Delete($targetPath, $false)
          }
          Write-Host "Removed existing reparse-point skill target before APM install: $targetPath"
        }
      }
    }
  }
}

function Reset-CatalogBuildDir {
  $buildDir = Get-CatalogBuildDir
  if (Test-Path -LiteralPath $buildDir) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force
  }

  New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
  New-Item -ItemType Directory -Path (Get-CatalogBuildSkillsRoot) -Force | Out-Null
}

function Reset-TrackedCatalogDir {
  $trackedDir = Get-TrackedCatalogDir
  if (Test-Path -LiteralPath $trackedDir) {
    Remove-Item -LiteralPath $trackedDir -Recurse -Force
  }

  New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
}

function Get-ManagedSkillContentDir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  $skillRoot = Get-TrackedCatalogSkillsRoot
  foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $SkillId)) {
    $skillRoot = Join-Path $skillRoot $segment
  }

  if (-not (Test-Path -LiteralPath (Join-Path $skillRoot "SKILL.md"))) {
    throw "Managed catalog skill missing SKILL.md: $skillRoot"
  }

  return $skillRoot
}

function Get-PrivateSkillContentDir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  $skillRoot = Get-PrivateSkillsRoot
  foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $SkillId)) {
    $skillRoot = Join-Path $skillRoot $segment
  }

  if (-not (Test-Path -LiteralPath (Join-Path $skillRoot "SKILL.md"))) {
    throw "Private skill missing SKILL.md: $skillRoot"
  }

  return $skillRoot
}

function Get-LocalSkillContentDir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId
  )

  $privateSkillRoot = Get-PrivateSkillsRoot
  foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $SkillId)) {
    $privateSkillRoot = Join-Path $privateSkillRoot $segment
  }

  if (Test-Path -LiteralPath (Join-Path $privateSkillRoot "SKILL.md")) {
    return $privateSkillRoot
  }

  return (Get-ManagedSkillContentDir -SkillId $SkillId)
}

function Copy-ManagedSkillIntoCatalog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SkillId,

    [Parameter(Mandatory = $true)]
    [string]$SkillsRoot
  )

  $sourceDir = Get-ManagedSkillContentDir -SkillId $SkillId
  $destinationDir = $SkillsRoot
  foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $SkillId)) {
    $destinationDir = Join-Path $destinationDir $segment
  }

  Copy-DirectoryContents -SourceDir $sourceDir -DestinationDir $destinationDir
}

function Copy-ManagedInstructionsIntoCatalog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  $sourcePath = Get-TrackedCatalogInstructionsPath
  if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Managed catalog instructions missing: $sourcePath"
  }

  Copy-ManagedCatalogFile -SourcePath $sourcePath -DestinationPath $DestinationPath
}

function Copy-ManagedAgentAssetsIntoCatalog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDir
  )

  $sourceDir = Get-TrackedCatalogAgentsRoot
  if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Managed catalog agents missing: $sourceDir"
  }

  Copy-DirectoryContents -SourceDir $sourceDir -DestinationDir $DestinationDir
}

function Copy-ManagedCommandAssetsIntoCatalog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDir
  )

  $sourceDir = Get-TrackedCatalogCommandsRoot
  if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Managed catalog commands missing: $sourceDir"
  }

  Copy-DirectoryContents -SourceDir $sourceDir -DestinationDir $DestinationDir
}

function Copy-ManagedRuleAssetsIntoCatalog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDir
  )

  $sourceDir = Get-TrackedCatalogRulesRoot
  if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Managed catalog rules missing: $sourceDir"
  }

  Copy-DirectoryContents -SourceDir $sourceDir -DestinationDir $DestinationDir
}

function Get-TrackedCatalogReference {
  $tracking = Get-WorkspaceTrackingInfo
  $repoReference = Get-WorkspaceRepoReference -RemoteName $tracking.RemoteName
  return "{0}/{1}#{2}" -f $repoReference, (Get-TrackedCatalogRelativePath), $tracking.BranchName
}

function Assert-TrackedCatalogPublished {
  $trackedRelativePath = Get-TrackedCatalogRelativePath
  $trackedDir = Get-TrackedCatalogDir

  if (-not (Test-Path -LiteralPath $trackedDir)) {
    throw "Tracked catalog missing: $trackedDir. Run 'mise run prepare:catalog' first."
  }

  $dirty = & git -C $WorkspaceDir status --porcelain -- $trackedRelativePath 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to inspect git status for $trackedRelativePath"
  }
  if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String))) {
    throw "Tracked catalog has uncommitted changes. Commit and push $trackedRelativePath before registering it."
  }

  $tracking = Get-WorkspaceTrackingInfo
  $upstream = "{0}/{1}" -f $tracking.RemoteName, $tracking.BranchName
  $unpushed = & git -C $WorkspaceDir rev-list "$upstream..HEAD" -- $trackedRelativePath 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to compare $trackedRelativePath against $upstream"
  }
  if (-not [string]::IsNullOrWhiteSpace(($unpushed | Out-String))) {
    throw "Tracked catalog has commits not on $upstream. Push the branch before registering it."
  }
}

function Invoke-SeedCatalogBuild {
  param(
    [string[]]$RequestedSkillIds,
    [switch]$LegacyAlias
  )

  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Ensure-WorkspaceMiseFile

  $skillIds = @(Get-RequestedCatalogSkillIds -RequestedSkillIds $RequestedSkillIds)
  if ($LegacyAlias) {
    Write-WarnLine "migrate is now a compatibility alias. Prefer 'prepare:catalog' for the catalog flow."
  }

  Reset-CatalogBuildDir
  $trackedManifest = Join-Path (Get-TrackedCatalogDir) "apm.yml"
  $trackedReadme = Join-Path (Get-TrackedCatalogDir) "README.md"
  if (-not (Test-Path -LiteralPath $trackedManifest)) {
    throw "Tracked catalog manifest is missing: $trackedManifest"
  }
  if (-not (Test-Path -LiteralPath $trackedReadme)) {
    throw "Tracked catalog README is missing: $trackedReadme"
  }
  Copy-Item -LiteralPath $trackedManifest -Destination (Join-Path (Get-CatalogBuildDir) "apm.yml") -Force
  Copy-Item -LiteralPath $trackedReadme -Destination (Join-Path (Get-CatalogBuildDir) "README.md") -Force
  Copy-ManagedInstructionsIntoCatalog -DestinationPath (Get-CatalogBuildInstructionsPath)
  Copy-ManagedAgentAssetsIntoCatalog -DestinationDir (Get-CatalogBuildAgentsRoot)
  Copy-ManagedCommandAssetsIntoCatalog -DestinationDir (Get-CatalogBuildCommandsRoot)
  Copy-ManagedRuleAssetsIntoCatalog -DestinationDir (Get-CatalogBuildRulesRoot)
  foreach ($skillId in $skillIds) {
    Copy-ManagedSkillIntoCatalog -SkillId $skillId -SkillsRoot (Get-CatalogBuildSkillsRoot)
  }

  Write-Host "Seeded catalog build at ~/.apm/.catalog-build/$CatalogDirName from: $($skillIds -join ', ')"
}

function Invoke-BundleCatalog {
  param(
    [string[]]$RequestedSkillIds
  )

  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Ensure-WorkspaceMiseFile

  Invoke-SeedCatalogBuild -RequestedSkillIds $RequestedSkillIds
  Write-Host "Built catalog package at ~/.apm/.catalog-build/$CatalogDirName"
}

function Invoke-StageCatalog {
  param(
    [string[]]$RequestedSkillIds
  )

  Invoke-BundleCatalog -RequestedSkillIds $RequestedSkillIds
  $trackedDir = Get-TrackedCatalogDir
  Reset-TrackedCatalogDir
  Copy-DirectoryContents -SourceDir (Get-CatalogBuildDir) -DestinationDir $trackedDir

  $reference = Get-TrackedCatalogReference
  Write-Host "Updated ~/.apm/catalog at $trackedDir"
  Write-Host "Candidate upstream ref: $reference"
  Write-Host "Push the updated apm-workspace repo before using 'apm install -g $reference'."
}

function Invoke-RegisterCatalog {
  param(
    [string[]]$RequestedSkillIds
  )

  Require-Apm
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Ensure-WorkspaceMiseFile
  Assert-TrackedCatalogPublished
  Invoke-ValidateCatalog

  $skillIds = @(Get-InternalCleanupSkillIds)
  Remove-InternalTargetReparsePoints -SkillIds $skillIds

  $reference = Get-TrackedCatalogReference
  Invoke-WorkspaceInstallCommand -InstallArgs @("-g", $reference)
  Sync-ManagedCatalogRuntimeAssets
  Write-Host "Registered catalog from upstream ref: $reference"
}

function Assert-CatalogReleaseReady {
  Ensure-WorkspaceRepo

  $dirty = & git -C $WorkspaceDir status --porcelain 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to inspect git status for $WorkspaceDir"
  }
  if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String))) {
    throw "Working tree is dirty after prepare:catalog. Commit or stash changes, push the branch, then rerun release:catalog."
  }

  $tracking = Get-WorkspaceTrackingInfo
  $upstream = "{0}/{1}" -f $tracking.RemoteName, $tracking.BranchName
  $unpushed = & git -C $WorkspaceDir rev-list "$upstream..HEAD" 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to compare HEAD against $upstream"
  }
  if (-not [string]::IsNullOrWhiteSpace(($unpushed | Out-String))) {
    throw "Branch has commits not on $upstream. Push before running release:catalog."
  }
}

function Invoke-ReleaseCatalog {
  param(
    [string[]]$RequestedSkillIds
  )

  Require-Apm
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Ensure-WorkspaceMiseFile

  Invoke-StageCatalog -RequestedSkillIds $RequestedSkillIds
  Assert-CatalogReleaseReady
  Invoke-RegisterCatalog -RequestedSkillIds $RequestedSkillIds
}

function Invoke-SmokeCatalog {
  param(
    [string[]]$RequestedSkillIds
  )

  Require-Apm

  $skillIds = @(Get-RequestedCatalogSkillIds -RequestedSkillIds $RequestedSkillIds)
  Invoke-BundleCatalog -RequestedSkillIds $skillIds

  $tempDir = Join-Path $env:TEMP ("apm-catalog-smoke-{0}" -f ([guid]::NewGuid().ToString("N")))
  $success = $false

  try {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Push-Location $tempDir
    try {
      & apm install (Get-CatalogBuildDir) --target codex
      if ($LASTEXITCODE -ne 0) {
        throw "apm install failed for catalog smoke test."
      }
    }
    finally {
      Pop-Location
    }

    foreach ($skillId in $skillIds) {
      $bundleSkillDir = Get-CatalogBuildSkillsRoot
      $installedSkillDir = Join-Path $tempDir ".agents/skills"
      $installedSkillName = Format-SkillName -Target "codex" -SourceSkillId $skillId
      foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $skillId)) {
        $bundleSkillDir = Join-Path $bundleSkillDir $segment
      }
      foreach ($segment in (Convert-SkillIdToPathSegments -SkillId $installedSkillName)) {
        $installedSkillDir = Join-Path $installedSkillDir $segment
      }
      $skillPath = Join-Path $installedSkillDir "SKILL.md"

      if (-not (Test-Path -LiteralPath $skillPath)) {
        throw "Smoke test failed: expected installed skill file missing: $skillPath"
      }

      $expectedFiles = @(Get-RelativeFilePaths -RootDir $bundleSkillDir)
      $installedFiles = @(Get-RelativeFilePaths -RootDir $installedSkillDir)
      if ((@($expectedFiles) -join "`n") -ne (@($installedFiles) -join "`n")) {
        throw ("Smoke test failed: installed skill tree for {0} differed from catalog.`nExpected:`n{1}`nActual:`n{2}" -f $skillId, ($expectedFiles -join "`n"), ($installedFiles -join "`n"))
      }
    }

    $success = $true
    Write-Host "Smoke verified catalog via temp project install: $($skillIds -join ', ')"
  }
  finally {
    if ($success) {
      Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path -LiteralPath $tempDir) {
      Write-WarnLine "Catalog smoke test workspace left at $tempDir for inspection."
    }
  }
}

if ($env:APM_WORKSPACE_LIB_ONLY -eq "1") {
  return
}

switch ($Command) {
  "apply" {
    Invoke-Apply
  }

  "apply:skills:local" {
    Invoke-SyncLocalSkills -RequestedSkillIds $CommandArgs
  }

  "refresh" {
    Invoke-Update
  }

  "pin-external" {
    Invoke-PinExternal
  }

  "validate" {
    Invoke-Validate
  }

  "validate:catalog" {
    Invoke-ValidateCatalog
  }

  "doctor" {
    Invoke-Doctor
  }

  "bundle-catalog" {
    Invoke-BundleCatalog -RequestedSkillIds $CommandArgs
  }

  "prepare:catalog" {
    Invoke-StageCatalog -RequestedSkillIds $CommandArgs
  }

  "install:catalog" {
    Invoke-RegisterCatalog -RequestedSkillIds $CommandArgs
  }

  "release:catalog" {
    Invoke-ReleaseCatalog -RequestedSkillIds $CommandArgs
  }

  "smoke:catalog" {
    Invoke-SmokeCatalog -RequestedSkillIds $CommandArgs
  }

  "help" {
    @"
Usage: scripts/apm-workspace.ps1 <command> [args...]

Commands:
  apply              Offline deploy user-scope-compatible dependencies and compile Codex output
  apply:skills:local Quick-sync local catalog and private skills into ~/.agents/skills only
  refresh            Refresh the checkout and dependencies only; does not deploy
  pin-external       Pin external manifest refs to lockfile commits
  validate           Validate the ~/.apm workspace
  validate:catalog   Fail when ~/.apm/catalog is not normalized or missing required assets
  doctor             Inspect workspace and target state
  bundle-catalog     Build ~/.apm/.catalog-build/catalog as the catalog package artifact
  prepare:catalog    Rewrite ~/.apm/catalog into its normalized publishable layout and print its upstream ref
  install:catalog    Install the catalog ref after commit/push
  release:catalog    Prepare, require a clean pushed branch, then install the catalog ref
  smoke:catalog      Smoke-test the generated catalog package via temp project install

Environment overrides:
  APM_WORKSPACE_DIR
  APM_WORKSPACE_REPO
  APM_WORKSPACE_NAME
  APM_CODEX_OUTPUT
"@ | Write-Host
  }

  default {
    throw "Unknown command: $Command"
  }
}
