<#
  probe.ps1 - what Suite-Setup.exe shows on its "Checking this PC" page.

  Writes an INI file the installer reads with GetIniString:
    [pc]     windows, ramGB, gpu, vramGB, ollamaRunning (1/0)
    [drives] count, d1..dN = letter|freeGB|sizeGB|filesystem|label|type (fixed/removable)
  With -Speed it instead times a short download and writes [net] mbps.
  With -Place "town or address" it looks the place up (OpenStreetMap's Nominatim, the same search
  Build Local Area uses) and writes [places] count, p1..pN = name|lat|lon|country code.
#>
param([Parameter(Mandatory = $true)][string]$Out, [switch]$Speed, [string]$Place = '')
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$lines = New-Object System.Collections.Generic.List[string]

if ($Place) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $found = @()
  $ua = @{ 'User-Agent' = 'AI-Research-Suite-Setup (github.com/DFranke84/AI-Research-Suite)' }
  try {
    if ($Place -match '^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$') {
      # a position: name it with a reverse lookup, keep the exact numbers
      $lat, $lon = $Matches[1], $Matches[2]
      $r = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2&addressdetails=1&zoom=12" -Headers $ua -TimeoutSec 20
      $found = @([pscustomobject]@{ display_name = $(if ($r.display_name) { $r.display_name } else { "$lat, $lon" }); lat = $lat; lon = $lon; address = $r.address })
      throw 'done'
    }
    $q = [Uri]::EscapeDataString($Place)
    # piped through ForEach-Object: Windows PowerShell hands a JSON array over as one object otherwise
    $found = @(Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/search?q=$q&format=jsonv2&addressdetails=1&limit=5" `
      -Headers @{ 'User-Agent' = 'AI-Research-Suite-Setup (github.com/DFranke84/AI-Research-Suite)' } -TimeoutSec 20 | ForEach-Object { $_ })
  } catch { if ("$_" -ne 'done') { $found = @() } }
  $lines.Add('[places]'); $lines.Add("count=$($found.Count)")
  $i = 0
  foreach ($p in $found) {
    $i++
    $name = ("$($p.display_name)" -replace '\|', ' ')
    $lines.Add(("p{0}={1}|{2}|{3}|{4}" -f $i, $name, $p.lat, $p.lon, "$($p.address.country_code)"))
  }
  [IO.File]::WriteAllLines($Out, $lines, [Text.Encoding]::Unicode)   # UTF-16 with BOM: Windows' INI reader keeps accented names
  exit 0
}

if ($Speed) {
  # 8 MB from the start of the Ollama download - a file the AI apps fetch anyway, from GitHub.
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $mbps = 0
  try {
    $req = [Net.HttpWebRequest]::Create('https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip')
    $req.UserAgent = 'AI-Research-Suite-Setup'
    $req.AddRange(0, 8MB - 1)
    $req.Timeout = 20000
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = $req.GetResponse()
    $stream = $resp.GetResponseStream()
    $buf = New-Object byte[] 65536; $total = 0
    while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $total += $n; if ($sw.Elapsed.TotalSeconds -gt 15) { break } }
    $resp.Close(); $sw.Stop()
    if ($total -gt 0 -and $sw.Elapsed.TotalSeconds -gt 0) { $mbps = [int][math]::Round($total * 8 / 1e6 / $sw.Elapsed.TotalSeconds) }
  } catch { $mbps = 0 }
  $lines.Add('[net]'); $lines.Add("mbps=$mbps")
  [IO.File]::WriteAllLines($Out, $lines)
  exit 0
}

$os = Get-CimInstance Win32_OperatingSystem
$ram = [int][math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)

# Graphics-card memory, the same way the apps' setup picks a model catalog:
# nvidia-smi is exact for NVIDIA; otherwise the driver's 64-bit figure in the registry.
$gpuName = (Get-CimInstance Win32_VideoController | Sort-Object AdapterRAM -Descending | Select-Object -First 1).Name
$vram = 0
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
  $row = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | Select-Object -First 1
  if ($row) { $p = $row -split ',\s*'; $gpuName = $p[0]; $vram = [int][math]::Round([double]$p[1] / 1024) }
}
if (-not $vram) {
  $best = 0
  Get-ItemProperty -Path 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -Name 'HardwareInformation.qwMemorySize' |
    ForEach-Object { $b = [double]$_.'HardwareInformation.qwMemorySize'; if ($b -gt $best) { $best = $b } }
  if ($best -gt 0) { $vram = [int][math]::Round($best / 1GB) }
}

# AMD cards need Ollama's ROCm add-on (the apps' setup -Rocm)
$amd = 0
if ($gpuName -match 'AMD|Radeon' -and $gpuName -notmatch 'NVIDIA') { $amd = 1 }

# optional library tools, found the way the library's own check_setup.py finds them
$bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ }
$browser = 0
foreach ($b in $bases) { foreach ($rel in 'Google\Chrome\Application\chrome.exe', 'Microsoft\Edge\Application\msedge.exe') { if (Test-Path (Join-Path $b $rel)) { $browser = 1 } } }
$antiword = 0
if (Get-Command antiword -ErrorAction SilentlyContinue) { $antiword = 1 }
foreach ($b in @($env:ProgramFiles, $env:LOCALAPPDATA) | Where-Object { $_ }) { foreach ($rel in 'Git\mingw64\bin\antiword.exe', 'Programs\Git\mingw64\bin\antiword.exe') { if (Test-Path (Join-Path $b $rel)) { $antiword = 1 } } }

$ollama = 0
try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 11434); $c.Close(); $ollama = 1 } catch { }

$lines.Add('[pc]')
$lines.Add("windows=$($os.Caption -replace '^Microsoft\s+', '')")
$lines.Add("ramGB=$ram")
$lines.Add("gpu=$gpuName")
$lines.Add("vramGB=$vram")
$lines.Add("ollamaRunning=$ollama")
$lines.Add("amd=$amd")
$lines.Add("browser=$browser")
$lines.Add("antiword=$antiword")

$disks = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 -and $_.Size } | Sort-Object DeviceID)
$lines.Add('[drives]')
$lines.Add("count=$($disks.Count)")
$i = 0
foreach ($d in $disks) {
  $i++
  $type = $(if ($d.DriveType -eq 2) { 'removable' } else { 'fixed' })
  $label = ("$($d.VolumeName)" -replace '\|', ' ')
  $lines.Add(("d{0}={1}|{2}|{3}|{4}|{5}|{6}" -f $i, $d.DeviceID, [math]::Floor($d.FreeSpace / 1e9), [math]::Floor($d.Size / 1e9), $d.FileSystem, $label, $type))
}
[IO.File]::WriteAllLines($Out, $lines)
