<#
  probe.ps1 - what Suite-Setup.exe shows on its "Checking this PC" page.

  Writes an INI file the installer reads with GetIniString:
    [pc]     windows, ramGB, gpu, vramGB, ollamaRunning (1/0)
    [drives] count, d1..dN = letter|freeGB|sizeGB|filesystem|label|type (fixed/removable)
  With -Speed it instead times a short download and writes [net] mbps.
#>
param([Parameter(Mandatory = $true)][string]$Out, [switch]$Speed)
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$lines = New-Object System.Collections.Generic.List[string]

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

$ollama = 0
try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 11434); $c.Close(); $ollama = 1 } catch { }

$lines.Add('[pc]')
$lines.Add("windows=$($os.Caption -replace '^Microsoft\s+', '')")
$lines.Add("ramGB=$ram")
$lines.Add("gpu=$gpuName")
$lines.Add("vramGB=$vram")
$lines.Add("ollamaRunning=$ollama")

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
