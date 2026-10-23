<#
  install.ps1 - does everything Suite-Setup.exe's wizard asked for. Safe to run again: every
  step skips what is already done, so after a stop (closed window, lost internet) running it
  again carries on. Suite-Setup.exe writes the choices to plan.ini next to this script.

    install.ps1                 use plan.ini
    install.ps1 -Plan file      use another plan file
    install.ps1 -Source dir     take the apps' release zips from a folder instead of GitHub

  plan.ini [plan]: app=full|slim|none, research=1/0, viewer=1/0, model=<ollama id>,
  voice=1/0, maps=key,key, packs=key,key (catalog.ini [packs] groups), wiki=none|nopic|maxi,
  background=1/0 (fetch Wikipedia in its own window after the rest), weekly=1/0, desktop=1/0
#>
param([string]$Plan = '', [string]$Source = '', [switch]$NoPause)   # -NoPause: nobody is watching (silent Setup)
$ErrorActionPreference = 'Stop'
$suiteDir = $PSScriptRoot
$root = Split-Path $suiteDir -Parent
if (-not $Plan) { $Plan = Join-Path $suiteDir 'plan.ini' }

function Read-Ini([string]$path) {
  $ini = @{}; $sec = ''
  foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
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
$wiki = "$($p['wiki'])"
$wikiKey = $(if ($wiki -in 'nopic', 'maxi') { "wikipedia-$wiki" } else { '' })
$wikiLater = $wikiKey -and (Flag $p['background'])

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
    if ($app -eq 'AIPortable') {
      $maps = @(List $p['maps']) + 'world'
      $a += @('-Maps', ($maps -join ','))
    }
    Run-Ps (Join-Path $root "$app\scripts\setup-windows.ps1") $a
  }
}
if ($research) {
  Add-Step 'Set up the Research library tools (Python)' {
    Run-Ps (Join-Path $root 'Research\_scripts\setup.ps1') @('-Yes', '-NoShortcut')   # Setup makes the shortcuts itself
  }
  $get = @($archiveKeys) + $(if ($wikiKey -and -not $wikiLater) { $wikiKey })
  if ($get.Count) {
    Add-Step "Download archives ($($get.Count))" { Run-Py (Join-Path $root 'Research\_scripts\get_archives.py') $get }
  }
  if ($packKeys.Count) {
    Add-Step "Build the starter library ($($packKeys.Count) packs)" { Run-Py (Join-Path $root 'Research\_scripts\build_starter.py') $packKeys }
  }
}
if ($viewer) {
  Add-Step 'Build the Library Viewer data' {
    if (-not (Test-Path (Join-Path $root 'Research\CATALOG.json'))) { Write-Host '  The library is still empty - build the viewer data after adding something (Build viewer data.bat).'; return }
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
Write-Host ''
Write-Host "AI Research Suite - installing into $root" -ForegroundColor Cyan
Write-Host 'You can close this window at any time; run Setup again and it carries on where it stopped.'
$failed = ''
$n = 0
foreach ($s in $steps) {
  $n++
  Write-Host ''
  Write-Host ("=== Step {0} of {1}: {2}" -f $n, $steps.Count, $s.Name) -ForegroundColor Cyan
  [IO.File]::WriteAllLines($state, @('[state]', 'result=running', "step=$n", "of=$($steps.Count)", "name=$($s.Name)", "log=$log"))
  try { & $s.Run }
  catch { $failed = "Step $n ($($s.Name)): $($_.Exception.Message)"; Write-Host "FAILED: $failed" -ForegroundColor Red; break }
}
$result = $(if ($failed) { 'failed' } else { 'ok' })
[IO.File]::WriteAllLines($state, @('[state]', "result=$result", "error=$failed", "log=$log", "wikiLater=$(if ($wikiLater -and -not $failed) { 1 } else { 0 })"))

if (-not $failed -and $wikiLater) {
  # Wikipedia is one very large file - fetched in its own window so the apps can be used meanwhile.
  Write-Host ''
  Write-Host "Starting the Wikipedia download ($wiki) in its own window..." -ForegroundColor Cyan
  Start-Process -FilePath (Join-Path $root 'Research\Get Archives.bat') -ArgumentList $wikiKey -WorkingDirectory (Join-Path $root 'Research')
}
Write-Host ''
if ($failed) { Write-Host "Setup stopped: $failed`nLog: $log" -ForegroundColor Red; if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null } }
else { Write-Host 'All done.' -ForegroundColor Green }
try { Stop-Transcript | Out-Null } catch { }
exit $(if ($failed) { 1 } else { 0 })
