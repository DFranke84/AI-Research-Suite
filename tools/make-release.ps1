<#
  make-release.ps1 - builds the code-only release zip for one suite component.

  Output (in -Out, default <suite repo>\dist):
    <Name>-<Version>.zip          the component's tracked files at that tag, plus
                                  release-manifest.json (version, commit, sha256 of every file)
    <Name>-<Version>.zip.sha256   "<hash>  <zip name>" - update.ps1 checks downloads against it

  Upload both to the GitHub release of the same tag (v<Version>).
  Nothing in the repo is changed; the zip is made from git, so untracked files
  (library content, models, node_modules, data) can never end up in it.

  Usage:
    tools\make-release.ps1 -Repo E:\AI-Research\AIPortable-JustAI            # tag v<VERSION file>
    tools\make-release.ps1 -Repo ..\Research -Version 1.2                    # tag v1.2
    tools\make-release.ps1 -Repo ..\Research -Ref HEAD -Version 1.2-test     # test build, no tag needed
#>
param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [string]$Version = '',
  [string]$Ref = '',
  [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$suiteDir = Split-Path $PSScriptRoot -Parent
if (-not $Out) { $Out = Join-Path $suiteDir 'dist' }
$Repo = (Resolve-Path $Repo).Path
$name = Split-Path $Repo -Leaf

$suite = Get-Content (Join-Path $suiteDir 'suite.json') -Raw | ConvertFrom-Json
$comp = $suite.components | Where-Object { $_.name -eq $name }
if (-not $comp) { throw "'$name' is not listed in suite.json" }

function Invoke-Git { & git -C $Repo @args; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

if (-not $Version) {
  $vf = Join-Path $Repo 'VERSION'
  if (-not (Test-Path $vf)) { throw "No -Version given and $name has no VERSION file" }
  $Version = (Get-Content $vf -Raw).Trim()
}
if (-not $Ref) { $Ref = "v$Version" }
& git -C $Repo rev-parse --verify --quiet "$Ref^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "$name has no '$Ref' (tag it first, or pass -Ref HEAD for a test build)" }
$commit = (Invoke-Git rev-parse "$Ref^{commit}").Trim()

# The tagged VERSION file must agree with the release version (older tags may have none).
$ErrorActionPreference = 'Continue'
$tagged = & git -C $Repo show "${Ref}:VERSION" 2>$null
$taggedOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = 'Stop'
if ($taggedOk -and $tagged -and ("$tagged".Trim() -ne $Version)) {
  throw "VERSION at $Ref says '$($tagged.Trim())', not '$Version'"
}

$work = Join-Path $env:TEMP "make-release-$name-$Version"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$tree = Join-Path $work 'tree'
New-Item -ItemType Directory -Force -Path $tree | Out-Null

Write-Host "Building $name $Version from $Ref ($($commit.Substring(0,7)))"
$rawZip = Join-Path $work 'git.zip'
Invoke-Git archive --format=zip -o $rawZip $Ref
[IO.Compression.ZipFile]::ExtractToDirectory($rawZip, $tree)
Remove-Item $rawZip
# Older tags have no VERSION file - add it so the installed copy always knows its version.
$vPath = Join-Path $tree 'VERSION'
if (-not (Test-Path $vPath)) { [IO.File]::WriteAllText($vPath, "$Version`r`n") }

$files = [ordered]@{}
Get-ChildItem $tree -Recurse -File | Sort-Object FullName | ForEach-Object {
  $rel = $_.FullName.Substring($tree.Length + 1) -replace '\\', '/'
  $files[$rel] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
}
$manifest = [ordered]@{
  name    = $name
  repo    = $comp.repo
  version = $Version
  commit  = $commit
  built   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  files   = $files
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $tree 'release-manifest.json') -Encoding UTF8

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$zipName = "$name-$Version.zip"
$zip = Join-Path $Out $zipName
if (Test-Path $zip) { Remove-Item $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($tree, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Set-Content -Path "$zip.sha256" -Value "$hash  $zipName" -Encoding ASCII
Remove-Item $work -Recurse -Force

$size = '{0:N1} MB' -f ((Get-Item $zip).Length / 1MB)
Write-Host "  $zipName  ($($files.Count) files, $size)"
Write-Host "  sha256 $hash"
