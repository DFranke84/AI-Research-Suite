<#
  install.ps1 - does everything Suite-Setup.exe's wizard asked for. Safe to run again: every
  step skips what is already done, and partial downloads are kept and continued, so after a stop
  (closed window, lost internet, power cut) running it again carries on.
  Suite-Setup.exe writes the choices to plan.ini next to this script.

    install.ps1                 use plan.ini
    install.ps1 -Plan file      use another plan file
    install.ps1 -Source dir     take the apps' release zips from a folder instead of GitHub

  plan.ini [plan]: app=full|slim|none, research=1/0, viewer=1/0, model=<ollama id>, rocm=1/0,
  voice=1/0, maps=key,key, packs=key,key (catalog.ini [packs] groups), wiki=none|nopic|maxi,
  archives=<catalog id>,... (more archives), tools=none|git|chrome|git,chrome (Research's optional tools),
  local=1/0 + localLat, localLon, localKm, localPerGroup, localTopoKm, localMap (Build Local Area),
  background=1/0 (fetch Wikipedia in its own window after the rest), weekly=1/0, desktop=1/0

  Where archives go: with the Research library, into Research\_sources\zim (the AI apps read them
  there); AIPortable without the library, into AIPortable\data\wikipedia.
#>
param([string]$Plan = '', [string]$Source = '', [switch]$NoPause)   # -NoPause: nobody is watching (silent Setup)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$suiteDir = $PSScriptRoot
$root = Split-Path $suiteDir -Parent
if (-not $Plan) { $Plan = Join-Path $suiteDir 'plan.ini' }

function Read-Ini([string]$path) {
  $ini = @{}; $sec = ''
  foreach ($line in Get-Content -LiteralPath $path) {   # no -Encoding: Setup's INI files may be ANSI or UTF-16
    if ($line -match '^\s*\[(.+)\]\s*$') { $sec = $Matches[1]; $ini[$sec] = @{} }
    elseif ($sec -and $line -match '^\s*([^=;#]+?)\s*=(.*)$') { $ini[$sec][$Matches[1]] = $Matches[2].Trim() }
  }
  return $ini
}
function Flag($v) { return "$v" -eq '1' }
function List($v) { return @("$v" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$p = (Read-Ini $Plan)['plan']
$cat = Read-Ini (Join-Path $suiteDir 'installer\catalog.ini')
if (-not $Source -and $p['source']) { $Source = $p['source'] }

$app = $(switch ($p['app']) { 'full' { 'AIPortable' } 'slim' { 'AIPortable-JustAI' } default { '' } })
$research = (Flag $p['research']) -or (Flag $p['viewer'])
$viewer = Flag $p['viewer']
$pieces = @($app, $(if ($research) { 'Research' }), $(if ($viewer) { 'LibraryViewer' }) | Where-Object { $_ })

# Starter-pack groups -> the packs and archives they stand for
$packKeys = @(); $archiveKeys = @()
foreach ($g in (List $p['packs'])) {
  $packKeys += List $cat["pack-$g"]['packs']
  $archiveKeys += List $cat["pack-$g"]['archives']
}
$local = $research -and (Flag $p['local'])
$wiki = "$($p['wiki'])"
$wikiKey = $(if ($wiki -in 'nopic', 'maxi') { "wikipedia-$wiki" } else { '' })
# the Wikipedia pack and Local Area read their articles from a local Wikipedia, so then it comes first
$wikiNeeded = $wikiKey -and $research -and (($packKeys -contains 'wikipedia') -or $local)
$wikiLater = $wikiKey -and $research -and (Flag $p['background']) -and -not $wikiNeeded
$extras = @(List $p['archives'])
$zimDir = $(if ($research) { Join-Path $root 'Research\_sources\zim' } elseif ($app -eq 'AIPortable') { Join-Path $root 'AIPortable\data\wikipedia' } else { '' })

# ---------------------------------------------------------------- downloads
# Save-Download: survives a bad connection. The partial file (<dest>.part) is kept, and a retry - or
# running setup again - carries on from the same byte (HTTP Range; If-Range makes a file that changed
# on the server start over). A stalled transfer is retried with growing waits. Optional SHA-256 check.
# (The same function is in AIPortable, AIPortable-JustAI and AI-Research-Suite - keep them alike.)
function Save-Download([string]$url, [string]$dest, [string]$sha256 = '', [int]$tries = 6) {
  $part = "$dest.part"; $info = "$dest.part.info"
  $etag = ''
  if (Test-Path -LiteralPath $part) {
    $saved = if (Test-Path -LiteralPath $info) { Get-Content -LiteralPath $info -Raw } else { '' }
    if ($saved -notmatch [regex]::Escape("url=$url")) { Remove-Item -LiteralPath $part -Force }   # left from another file
    elseif ($saved -match 'etag=(.+)') { $etag = $Matches[1].Trim() }
  }
  $mb = { param($b) if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
  for ($try = 1; $try -le $tries; $try++) {
    $have = if (Test-Path -LiteralPath $part) { (Get-Item -LiteralPath $part).Length } else { 0 }
    $total = -1
    try {
      $req = [Net.HttpWebRequest]::Create($url)
      $req.UserAgent = 'AI-Research-Suite-Setup'
      $req.Timeout = 30000; $req.ReadWriteTimeout = 60000
      if ($have -gt 0) {
        $req.AddRange([long]$have)
        if ($etag) { $req.Headers['If-Range'] = $etag }
        Write-Host ("    continuing from {0}" -f (& $mb $have))
      }
      $resp = $req.GetResponse()
      try {
        if ($have -gt 0 -and [int]$resp.StatusCode -ne 206) { $have = 0 }   # the whole file came back: start over
        if ($resp.ContentLength -ge 0) { $total = $resp.ContentLength + $have }
        $tag = "$($resp.Headers['ETag'])"
        if ($tag -and $tag -notmatch '^W/') { $etag = $tag } else { $etag = '' }
        [IO.File]::WriteAllText($info, "url=$url`r`netag=$etag`r`n")
        $mode = if ($have -gt 0) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
        $out = [IO.File]::Open($part, $mode, [IO.FileAccess]::Write)
        try {
          $in = $resp.GetResponseStream()
          $buf = New-Object byte[] (1MB)
          $done = $have; $shown = [DateTime]::Now
          while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $done += $n
            if (([DateTime]::Now - $shown).TotalSeconds -ge 5) {
              $shown = [DateTime]::Now
              Write-Host -NoNewline ("`r    {0} of {1}      " -f (& $mb $done), $(if ($total -gt 0) { & $mb $total } else { '?' }))
            }
          }
        } finally { $out.Close() }
      } finally { $resp.Close() }
      $got = (Get-Item -LiteralPath $part).Length
      if ($total -gt 0 -and $got -lt $total) { throw "the connection closed at $(& $mb $got) of $(& $mb $total)" }
      Write-Host ''
      if ($sha256 -and (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -ne $sha256.ToUpper()) {
        Remove-Item -LiteralPath $part, $info -Force
        throw 'the download is damaged (checksum does not match) - it will start again'
      }
      Move-Item -LiteralPath $part -Destination $dest -Force
      Remove-Item -LiteralPath $info -Force -ErrorAction SilentlyContinue
      return
    } catch {
      $msg = $_.Exception.Message
      $resp416 = $_.Exception.InnerException.Response
      if (-not $resp416) { $resp416 = $_.Exception.Response }
      if ($resp416 -and [int]$resp416.StatusCode -eq 416) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }   # the kept part no longer fits
      Write-Host ''
      if ($try -ge $tries) { throw "$msg (tried $tries times; the part already downloaded is kept - run setup again to continue)" }
      $wait = 10 * $try
      Write-Host "    connection problem ($msg) - trying again in $wait s" -ForegroundColor Yellow
      Start-Sleep -Seconds $wait
    }
  }
}

# One archive from AIPortable's catalog (data\wikipedia-catalog.json), newest version from Kiwix.
# In the library folder it keeps Kiwix's dated name (as Get Archives does); in AIPortable's folder
# it gets the catalog name, so AIPortable's Wikipedia tab shows it as downloaded.
function Get-Archive([string]$id, [string]$kiwixFolder, [string]$destDir, [bool]$dated) {
  $stem = $id -replace '\.zim$', ''
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $have = @(Get-ChildItem -LiteralPath $destDir -Filter '*.zim' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $id -or $_.Name -match ('^' + [regex]::Escape($stem) + '_\d{4}-\d{2}[a-z]?\.zim$') })
  if ($have.Count) { Write-Host "  $id - already here ($($have[0].Name))"; return }
  $folderUrl = "https://download.kiwix.org/zim/$kiwixFolder/"
  $listing = (Invoke-WebRequest -Uri $folderUrl -UseBasicParsing -TimeoutSec 60).Content
  $names = @([regex]::Matches($listing, 'href="(' + [regex]::Escape($stem) + '_(\d{4}-\d{2}[a-z]?)\.zim)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (-not $names.Count) { throw "Kiwix has no current $id" }
  $name = $names | Sort-Object { ($_ -replace '^.*_(\d{4}-\d{2}[a-z]?)\.zim$', '$1') } | Select-Object -Last 1
  $url = $folderUrl + $name
  $sha = ''
  try { $sha = ("$((Invoke-WebRequest -Uri "$url.sha256" -UseBasicParsing -TimeoutSec 60).Content)" -split '\s+')[0] } catch { }
  $dest = Join-Path $destDir $(if ($dated) { $name } else { $id })
  Write-Host "  $name"
  Save-Download $url $dest $sha
}

function Catalog-Entry([string]$id) {
  $n = [int]$cat['archives']['count']
  for ($i = 1; $i -le $n; $i++) {
    $row = $cat['archives']["a$i"] -split '\|'
    if ($row[0] -eq $id) { return $row }
  }
  return $null
}

# ---------------------------------------------------------------- steps
$steps = New-Object System.Collections.Generic.List[object]
function Add-Step([string]$name, [scriptblock]$run) { $steps.Add([pscustomobject]@{ Name = $name; Run = $run }) }

$ps = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
function Run-Ps([string]$file, [string[]]$arguments) {
  & powershell.exe @ps $file @arguments
  if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $file -Leaf) stopped with an error (exit $LASTEXITCODE)" }
}
$py = Join-Path $root 'Research\_scripts\.venv\Scripts\python.exe'
function Run-Py([string]$script, [string[]]$arguments) {
  $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
  & $py -u $script @arguments
  if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $script -Leaf) stopped with an error (exit $LASTEXITCODE)" }
}

Add-Step "Download the program files ($($pieces -join ', '))" {
  $a = @('-Install', ($pieces -join ','), '-Only', ($pieces -join ','), '-Yes')
  if ($Source) { $a += @('-Source', $Source) }
  Run-Ps (Join-Path $suiteDir 'update.ps1') $a
}
if ($app) {
  Add-Step "Set up $app (Node.js, Electron, Ollama, Kiwix$(if (Flag $p['voice']) { ', voice input' }), AI models)" {
    $a = @('-Model', $p['model'], '-NoLaunch')
    if (-not (Flag $p['voice'])) { $a += '-NoVoice' }
    if (Flag $p['rocm']) { $a += '-Rocm' }   # AMD graphics card
    if ($app -eq 'AIPortable') {
      $maps = @(List $p['maps']) + 'world'
      $a += @('-Maps', ($maps -join ','))
    }
    Run-Ps (Join-Path $root "$app\scripts\setup-windows.ps1") $a
  }
}
if ($research) {
  Add-Step 'Set up the Research library tools (Python)' {
    $tools = $(if ($p['tools']) { $p['tools'] } else { 'none' })
    Run-Ps (Join-Path $root 'Research\_scripts\setup.ps1') @('-Yes', '-NoShortcut', '-OptionalTools', $tools)   # Setup makes the shortcuts itself
    # an empty catalog, so the AI apps link the library (and its archives) from their first start
    if (-not (Test-Path (Join-Path $root 'Research\CATALOG.json'))) { Run-Py (Join-Path $root 'Research\_scripts\20_catalog.py') @() }
  }
  if ($wikiNeeded) {
    Add-Step "Download Wikipedia first ($wiki) - the Wikipedia pack and Local Area read their articles from it" {
      Run-Py (Join-Path $root 'Research\_scripts\get_archives.py') @($wikiKey)
    }
  }
  $get = @($archiveKeys) + $(if ($wikiKey -and -not $wikiNeeded -and -not $wikiLater) { $wikiKey })
  if ($get.Count) {
    Add-Step "Download the starter-pack archives ($($get.Count))" { Run-Py (Join-Path $root 'Research\_scripts\get_archives.py') $get }
  }
  if ($packKeys.Count) {
    Add-Step "Build the starter library ($($packKeys.Count) packs)" { Run-Py (Join-Path $root 'Research\_scripts\build_starter.py') $packKeys }
  }
  if ($local) {
    Add-Step "Build your Local Area ($($p['localKm']) km around $($p['localName']))" {
      $a = @('--place', "$($p['localLat']), $($p['localLon'])", '--radius', $p['localKm'], '--per-group', $p['localPerGroup'], '--yes')
      if ([int]$p['localTopoKm'] -gt 0) { $a += @('--maps', $p['localTopoKm']) } else { $a += '--no-maps' }
      Run-Py (Join-Path $root 'Research\_scripts\build_local_area.py') $a
      if ((Flag $p['localMap']) -and $app -eq 'AIPortable') {
        # Build Local Area added 'my-area' to AIPortable's map list - fetch it now
        Run-Ps (Join-Path $root 'AIPortable\resources\maps\DOWNLOAD-MAPS.ps1') @('-Regions', 'my-area')
      }
    }
  }
}
if ($zimDir -and ($extras.Count -or ($wikiKey -and -not $research))) {
  Add-Step "Download offline archives ($(@($extras).Count + $(if ($wikiKey -and -not $research) { 1 } else { 0 })))" {
    if ($wikiKey -and -not $research) { Get-Archive "wikipedia_en_all_$wiki.zim" 'wikipedia' $zimDir $false }
    foreach ($id in $extras) {
      $row = Catalog-Entry $id
      if (-not $row) { Write-Host "  $id - not in the catalog, skipped" -ForegroundColor Yellow; continue }
      Get-Archive $id $row[4] $zimDir $research
    }
  }
}
if ($viewer) {
  Add-Step 'Build the Library Viewer data' {
    $c = Join-Path $root 'Research\CATALOG.json'
    if (-not (Test-Path $c) -or (Get-Item $c).Length -lt 10) { Write-Host '  The library is still empty - build the viewer data after adding something (Build viewer data.bat).'; return }
    Run-Py (Join-Path $root 'LibraryViewer\_build\build_viewer.py') @('--library', (Join-Path $root 'Research'))
  }
}
Add-Step 'Save settings and check everything' {
  $sp = Join-Path $suiteDir 'settings.json'
  $s = @{}
  if (Test-Path $sp) { (Get-Content $sp -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $s[$_.Name] = $_.Value } }
  $s['weeklyCheck'] = Flag $p['weekly']
  $s | ConvertTo-Json | Set-Content -Path $sp -Encoding ASCII
  foreach ($n in $pieces) {
    if (-not (Test-Path (Join-Path $root "$n\release-manifest.json"))) { throw "$n is not installed" }
  }
}

# ---------------------------------------------------------------- run
$logDir = Join-Path $suiteDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("install-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd-HHmmss'))
$state = Join-Path $suiteDir 'install-state.ini'
try { Start-Transcript -Path $log | Out-Null } catch { }
$host.UI.RawUI.WindowTitle = 'AI Research Suite - installing'

# Keep the PC awake while this runs (a sleeping PC drops the downloads); the screen may still turn off.
# Windows goes back to its normal sleep settings when this window closes.
Add-Type -Namespace Suite -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
[void][Suite.Power]::SetThreadExecutionState([uint32]'0x80000001')   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED

Write-Host ''
Write-Host "AI Research Suite - installing into $root" -ForegroundColor Cyan
Write-Host 'The PC is kept awake until this finishes. You can close this window at any time: everything'
Write-Host 'already downloaded is kept, and running Setup again carries on where it stopped.'
$failed = ''
$n = 0
$tries = 3
foreach ($s in $steps) {
  $n++
  for ($try = 1; $try -le $tries; $try++) {
    Write-Host ''
    Write-Host ("=== Step {0} of {1}: {2}{3}" -f $n, $steps.Count, $s.Name, $(if ($try -gt 1) { " (try $try of $tries)" } else { '' })) -ForegroundColor Cyan
    [IO.File]::WriteAllLines($state, @('[state]', 'result=running', "step=$n", "of=$($steps.Count)", "name=$($s.Name)", "log=$log"))
    try { & $s.Run; $failed = ''; break }
    catch {
      $failed = "Step $n of $($steps.Count) ($($s.Name)): $($_.Exception.Message)"
      if ($try -lt $tries) {
        Write-Host "That step stopped: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Trying it again in 60 s (what is already done is kept)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
      }
    }
  }
  if ($failed) { Write-Host "FAILED: $failed" -ForegroundColor Red; break }
}
$result = $(if ($failed) { 'failed' } else { 'ok' })
[IO.File]::WriteAllLines($state, @('[state]', "result=$result", "error=$failed", "log=$log", "wikiLater=$(if ($wikiLater -and -not $failed) { 1 } else { 0 })"))
[void][Suite.Power]::SetThreadExecutionState([uint32]'0x80000000')   # back to normal sleep

if (-not $failed -and $wikiLater) {
  # Wikipedia is one very large file - fetched in its own window so the apps can be used meanwhile.
  Write-Host ''
  Write-Host "Starting the Wikipedia download ($wiki) in its own window..." -ForegroundColor Cyan
  Start-Process -FilePath (Join-Path $root 'Research\Get Archives.bat') -ArgumentList $wikiKey -WorkingDirectory (Join-Path $root 'Research')
}
Write-Host ''
if ($failed) {
  Write-Host "Setup stopped after $tries tries - $failed" -ForegroundColor Red
  Write-Host 'Everything downloaded so far is kept. Check the internet connection, then run Setup again'
  Write-Host "('Update and repair'): it carries on where it stopped. Log: $log"
  if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
}
else { Write-Host 'All done.' -ForegroundColor Green }
try { Stop-Transcript | Out-Null } catch { }
exit $(if ($failed) { 1 } else { 0 })
