<#
  update.ps1 - checks for and installs new versions of the AI Research Suite.

  Each piece of the suite (see suite.json) sits in its own folder next to this
  one. A new version is a GitHub release with a code-only zip. Updating replaces
  ONLY the program files listed in that zip's release-manifest.json - chats,
  models, maps, the library, notes and settings are never touched. Every file
  that is replaced or removed is saved first in AI-Research-Suite\backups\, so
  -Rollback can put the previous version back.

  Double-click "Check for updates.bat", or run:
    update.ps1                       check, list what's new, ask, then update
    update.ps1 -Check                only report (add -Json for the apps)
    update.ps1 -Yes                  update everything without asking
    update.ps1 -Only Research        limit to some pieces (comma-separated)
    update.ps1 -Install LibraryViewer     add a piece that isn't installed yet
    update.ps1 -Source F:\Updates    use release zips from a folder (USB stick,
                                     no internet needed) instead of GitHub
    update.ps1 -Rollback Research    undo the last update of a piece
    -WaitPid n      wait for that program (the app that started us) to close
    -SkipPostSteps  don't re-run a piece's setup after its dependencies changed
    -Root path      the suite folder (default: the folder above this script)

  Folders that are git checkouts (they have .git) are left alone: use git pull.
#>
param(
  [switch]$Check,
  [switch]$Json,
  [switch]$Yes,
  [string[]]$Only = @(),
  [string[]]$Install = @(),
  [string]$Source = '',
  [string]$Rollback = '',
  [int]$WaitPid = 0,
  [switch]$SkipPostSteps,
  [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$suiteDir = $PSScriptRoot
if (-not $Root) { $Root = Split-Path $suiteDir -Parent }
$Root = (Resolve-Path $Root).Path
$suite = Get-Content (Join-Path $suiteDir 'suite.json') -Raw | ConvertFrom-Json
$Only = @($Only -split ',' | Where-Object { $_ })
$Install = @($Install -split ',' | Where-Object { $_ })
$backupRoot = Join-Path $suiteDir 'backups'
$logDir = Join-Path $suiteDir 'logs'

function Say([string]$text, [string]$color = 'Gray') { if (-not $Json) { Write-Host $text -ForegroundColor $color } }

function ToVersion([string]$v) {
  $v = "$v".Trim() -replace '^[vV]', ''
  $core = ($v -split '[-+ ]')[0]
  if ($core -notmatch '\.') { $core = "$core.0" }
  try { return [version]$core } catch { return [version]'0.0' }
}

function Read-Json([string]$path) {
  if (Test-Path $path) { return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
  return $null
}

function Get-Installed($c) {
  $folder = Join-Path $Root $c.name
  $info = [ordered]@{ folder = $folder; present = (Test-Path $folder); git = $false; version = ''; manifest = $null }
  if (-not $info.present) { return $info }
  $info.git = Test-Path (Join-Path $folder '.git')
  $info.manifest = Read-Json (Join-Path $folder 'release-manifest.json')
  if ($info.manifest) { $info.version = $info.manifest.version }
  elseif (Test-Path (Join-Path $folder 'VERSION')) { $info.version = (Get-Content (Join-Path $folder 'VERSION') -Raw).Trim() }
  return $info
}

# Newest release of one component: from -Source (a folder of zips) or from GitHub.
function Get-Latest($c) {
  if ($Source) {
    $best = $null
    Get-ChildItem -Path $Source -Filter "$($c.name)-*.zip" -File -ErrorAction SilentlyContinue | ForEach-Object {
      $v = $_.BaseName.Substring($c.name.Length + 1)
      if ($v -notmatch '^\d') { return }    # e.g. AIPortable-JustAI-1.2.zip is not an AIPortable release
      if (-not $best -or (ToVersion $v) -gt (ToVersion $best.version)) {
        $notesFile = "$($_.FullName).notes.txt"
        $best = [ordered]@{ version = $v; zip = $_.FullName; sha = "$($_.FullName).sha256"; page = ''
                            notes = $(if (Test-Path $notesFile) { (Get-Content $notesFile -Raw).Trim() } else { '' }) }
      }
    }
    return $best
  }
  $api = "https://api.github.com/repos/$($c.repo)/releases/latest"
  $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'AI-Research-Suite-Updater'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20
  $v = "$($rel.tag_name)" -replace '^[vV]', ''
  $zipAsset = $rel.assets | Where-Object { $_.name -eq "$($c.name)-$v.zip" } | Select-Object -First 1
  $shaAsset = $rel.assets | Where-Object { $_.name -eq "$($c.name)-$v.zip.sha256" } | Select-Object -First 1
  return [ordered]@{ version = $v; page = $rel.html_url; notes = "$($rel.body)".Trim()
                     zip = $(if ($zipAsset) { $zipAsset.browser_download_url } else { '' })
                     sha = $(if ($shaAsset) { $shaAsset.browser_download_url } else { '' }) }
}

function First-Line([string]$text) {
  $line = ($text -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | Select-Object -First 1)
  if (-not $line) { return '' }
  $line = $line.Trim() -replace '^[-*]\s*', ''
  if ($line.Length -gt 110) { $line = $line.Substring(0, 107) + '...' }
  return $line
}

# Programs running from inside a folder (they lock files on Windows).
function Get-Running([string]$folder) {
  $prefix = $folder.TrimEnd('\') + '\'
  @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      try { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
}

function Wait-Closed([string]$folder, [string]$title) {
  if ($WaitPid) { try { Wait-Process -Id $WaitPid -Timeout 120 -ErrorAction Stop } catch { } }
  for ($i = 0; $i -lt 60; $i++) {
    $running = Get-Running $folder
    if (-not $running.Count) { return }
    if ($i -eq 0) { Say "    Waiting for $title to close ($(($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '))..." 'Yellow' }
    Start-Sleep -Seconds 2
  }
  throw "$title is still running - close it and try again"
}

function Get-Bytes($from, [string]$to) {
  if ($from -match '^https?://') {
    Invoke-WebRequest -Uri $from -OutFile $to -UseBasicParsing -Headers @{ 'User-Agent' = 'AI-Research-Suite-Updater' } -TimeoutSec 600
  } else { Copy-Item -LiteralPath $from -Destination $to -Force }
}

function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

function Remove-OldBackups([string]$name) {
  Get-ChildItem $backupRoot -Directory -Filter "$name-*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -Skip 3 | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
}

# Install or update one component from its release zip.
function Update-Component($c, $inst, $latest) {
  $folder = $inst.folder
  $title = $c.title
  $work = Join-Path $env:TEMP "suite-update-$($c.name)-$($latest.version)"
  if (Test-Path $work) { Remove-Item $work -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  try {
    if (-not $latest.zip) { throw "the $($latest.version) release has no $($c.name)-$($latest.version).zip to install" }
    Say "    Downloading $($c.name)-$($latest.version).zip"
    $zip = Join-Path $work 'release.zip'
    Get-Bytes $latest.zip $zip
    if (-not $latest.sha) { throw 'the release has no .sha256 file to check the download against' }
    Get-Bytes $latest.sha (Join-Path $work 'release.sha256')
    $want = ((Get-Content (Join-Path $work 'release.sha256') -Raw).Trim() -split '\s+')[0].ToLower()
    if ((Hash $zip) -ne $want) { throw 'the download is damaged (checksum does not match) - try again' }

    $new = Join-Path $work 'new'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $new)
    $newMan = Read-Json (Join-Path $new 'release-manifest.json')
    if (-not $newMan -or $newMan.name -ne $c.name) { throw 'the zip is not a release of this piece' }
    $newFiles = @{}; $newMan.files.PSObject.Properties | ForEach-Object { $newFiles[$_.Name] = $_.Value }
    $oldFiles = @{}
    if ($inst.manifest) { $inst.manifest.files.PSObject.Properties | ForEach-Object { $oldFiles[$_.Name] = $_.Value } }

    # Work out what changes. A file whose copy on disk already matches is left alone.
    $toCopy = New-Object System.Collections.Generic.List[string]
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $newFiles.Keys) {
      $dest = Join-Path $folder $rel
      if (-not (Test-Path -LiteralPath $dest)) { $toCopy.Add($rel); $added.Add($rel) }
      elseif ((Hash $dest) -ne $newFiles[$rel]) { $toCopy.Add($rel) }
    }
    $toRemove = @($oldFiles.Keys | Where-Object { -not $newFiles.ContainsKey($_) -and (Test-Path -LiteralPath (Join-Path $folder $_)) })
    $edited = @($toCopy | Where-Object { $oldFiles.ContainsKey($_) -and -not $added.Contains($_) -and (Hash (Join-Path $folder $_)) -ne $oldFiles[$_] })

    if ($inst.present) { Wait-Closed $folder $title }

    # Back up everything that will be replaced or removed (a fresh install has nothing to save).
    $mf = Join-Path $folder 'release-manifest.json'
    if ($inst.present) {
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      $oldLabel = $(if ($inst.version) { $inst.version } else { 'unknown' })
      $bak = Join-Path $backupRoot "$($c.name)-$stamp-from-$oldLabel"
      New-Item -ItemType Directory -Force -Path (Join-Path $bak 'files') | Out-Null
      foreach ($rel in @($toCopy | Where-Object { -not $added.Contains($_) }) + $toRemove) {
        $src = Join-Path $folder $rel
        $dst = Join-Path (Join-Path $bak 'files') $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
      }
      if (Test-Path $mf) { Copy-Item $mf (Join-Path $bak 'release-manifest.json') }
      Set-Content -Path (Join-Path $bak 'added.txt') -Value ($added -join "`r`n") -Encoding UTF8
      Set-Content -Path (Join-Path $bak 'info.txt') -Encoding UTF8 -Value "$($c.name): $oldLabel -> $($latest.version) on $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    }

    # Apply.
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    foreach ($rel in $toCopy) {
      $dst = Join-Path $folder $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      Copy-Item -LiteralPath (Join-Path $new $rel) -Destination $dst -Force
    }
    foreach ($rel in $toRemove) { Remove-Item -LiteralPath (Join-Path $folder $rel) -Force }
    Copy-Item (Join-Path $new 'release-manifest.json') $mf -Force
    Remove-OldBackups $c.name

    Say ("    {0} files updated, {1} added, {2} removed" -f ($toCopy.Count - $added.Count), $added.Count, $toRemove.Count) 'Green'
    if ($edited.Count) { Say "    You had changed $($edited.Count) of these files yourself - your copies are in $bak\files" 'Yellow' }

    # Re-run the piece's setup when its dependencies changed.
    if ($inst.present) {
      foreach ($p in @($c.postUpdate)) {
        if (-not $p) { continue }
        $hit = @($p.ifChanged | Where-Object { $toCopy.Contains($_) })
        if (-not $hit.Count) { continue }
        if ($SkipPostSteps) { Say "    $($hit -join ', ') changed - run $($p.run) yourself to finish (-SkipPostSteps)" 'Yellow'; continue }
        Say "    $($hit -join ', ') changed - running $($p.run)"
        $fresh = $null
        if ($p.freshFolder -and (Test-Path (Join-Path $folder $p.freshFolder))) {
          $fresh = Join-Path $folder $p.freshFolder
          if (Test-Path "$fresh.old") { Remove-Item "$fresh.old" -Recurse -Force }
          Rename-Item $fresh "$(Split-Path $fresh -Leaf).old"
        }
        $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $folder $p.run)) + @($p.args)
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
          if ($fresh) { Remove-Item "$fresh.old" -Recurse -Force -ErrorAction SilentlyContinue }
        } else {
          if ($fresh) {
            if (Test-Path $fresh) { Remove-Item $fresh -Recurse -Force -ErrorAction SilentlyContinue }
            Rename-Item "$fresh.old" (Split-Path $fresh -Leaf)
          }
          throw "$($p.run) failed (exit $($proc.ExitCode)) - the old dependencies were put back; run it again to see the error"
        }
      }
    }
  } finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Undo-Update($c) {
  $inst = Get-Installed $c
  if ($inst.git) { throw "$($c.name) is a git checkout - use git to go back" }
  $bak = Get-ChildItem $backupRoot -Directory -Filter "$($c.name)-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if (-not $bak) { throw "No saved earlier version of $($c.name) in $backupRoot" }
  Say "Rolling back $($c.name): $((Get-Content (Join-Path $bak.FullName 'info.txt') -Raw).Trim())" 'Cyan'
  Wait-Closed $inst.folder $c.title
  $files = Join-Path $bak.FullName 'files'
  foreach ($rel in @(Get-Content (Join-Path $bak.FullName 'added.txt') -ErrorAction SilentlyContinue | Where-Object { $_ })) {
    $p = Join-Path $inst.folder $rel
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
  }
  if (Test-Path $files) {
    Get-ChildItem $files -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($files.Length + 1)
      $dst = Join-Path $inst.folder $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
  }
  $mf = Join-Path $inst.folder 'release-manifest.json'
  $oldMf = Join-Path $bak.FullName 'release-manifest.json'
  if (Test-Path $oldMf) { Copy-Item $oldMf $mf -Force } elseif (Test-Path $mf) { Remove-Item $mf -Force }
  Remove-Item $bak.FullName -Recurse -Force
  Say "  Done. If that version used different dependencies, run its setup again." 'Green'
}

# ---------------------------------------------------------------- main
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("update-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
if (-not $Json) { try { Start-Transcript -Path $log -Append | Out-Null } catch { } }
$exit = 0
try {
  if ($Rollback) {
    $c = $suite.components | Where-Object { $_.name -eq $Rollback }
    if (-not $c) { throw "Unknown piece '$Rollback' - see suite.json" }
    Undo-Update $c
    return
  }

  $rows = @()
  foreach ($c in $suite.components) {
    if ($Only.Count -and $Only -notcontains $c.name -and $Install -notcontains $c.name) { continue }
    $inst = Get-Installed $c
    $wanted = $inst.present -or ($Install -contains $c.name)
    if (-not $wanted) { continue }
    $row = [ordered]@{ name = $c.name; title = $c.title; installed = $inst.version; latest = ''; update = $false
                       status = ''; notes = ''; page = ''; c = $c; inst = $inst; rel = $null }
    try {
      $rel = Get-Latest $c
      if (-not $rel) { $row.status = 'no release found' }
      else {
        $row.rel = $rel; $row.latest = $rel.version; $row.notes = First-Line $rel.notes; $row.page = $rel.page
        if ($inst.git) { $row.status = 'git checkout - use git pull' }
        elseif (-not $inst.present) { $row.update = $true; $row.status = 'not installed' }
        elseif ((ToVersion $rel.version) -gt (ToVersion $inst.version)) { $row.update = $true; $row.status = 'update available' }
        else { $row.status = 'up to date' }
      }
    } catch { $row.status = "could not check ($($_.Exception.Message))" }
    $rows += $row
  }

  if ($Json) {
    $out = [ordered]@{
      checked = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
      source = $(if ($Source) { $Source } else { 'github.com' })
      updates = @($rows | Where-Object { $_.update }).Count
      components = @($rows | ForEach-Object { [ordered]@{ name = $_.name; title = $_.title; installed = $_.installed; latest = $_.latest
                                                         update = $_.update; status = $_.status; notes = $_.notes; page = $_.page } })
    }
    $out | ConvertTo-Json -Depth 4
    if ($Check) { return }
  }

  Say ''
  Say "AI Research Suite - $Root" 'Cyan'
  Say "Checked $(if ($Source) { $Source } else { 'github.com' })"
  foreach ($r in $rows) {
    $color = $(if ($r.update) { 'Yellow' } elseif ($r.status -eq 'up to date') { 'Green' } else { 'Gray' })
    $ver = $(if ($r.installed) { $r.installed } else { '-' })
    if ($r.latest -and $r.update) { $ver = "$ver -> $($r.latest)" }
    Say ("  {0,-20} {1,-14} {2}" -f $r.name, $ver, $r.status) $color
    if ($r.update -and $r.notes) { Say "      $($r.notes)" }
  }
  $todo = @($rows | Where-Object { $_.update })
  if (-not $todo.Count) { Say ''; Say 'Nothing to update.' 'Green'; return }
  if ($Check) { return }

  if (-not $Yes) {
    Say ''
    Say 'Only program files are replaced. Chats, models, maps, the library and settings stay as they are.'
    $a = Read-Host "Update $($todo.Count) piece(s) now? [Y/n]"
    if ($a -and $a -notmatch '^[yY]') { Say 'Nothing changed.'; return }
  }
  foreach ($r in $todo) {
    Say ''
    Say "$($r.title): $(if ($r.installed) { $r.installed } else { 'new' }) -> $($r.latest)" 'Cyan'
    try { Update-Component $r.c $r.inst $r.rel }
    catch { Say "    FAILED: $($_.Exception.Message)" 'Red'; $exit = 1 }
  }
  Say ''
  if ($exit) { Say "Some updates failed - see above. Log: $log" 'Red' } else { Say 'All done.' 'Green' }
} catch {
  Say "ERROR: $($_.Exception.Message)" 'Red'
  if ($Json) { [ordered]@{ error = $_.Exception.Message } | ConvertTo-Json }
  $exit = 1
} finally {
  if (-not $Json) { try { Stop-Transcript | Out-Null } catch { } }
}
exit $exit
