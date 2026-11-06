<#
.SYNOPSIS
  One-shot ComfyUI setup for Windows + AMD Strix Halo (gfx1151): portable build + ROCm PyTorch.

.DESCRIPTION
  Downloads the official ComfyUI Windows portable build, extracts it, replaces the bundled CUDA
  PyTorch with the gfx1151 ROCm Windows wheels, verifies that the GPU is visible, and writes a
  launcher plus an optional idle-exit supervisor.

.PARAMETER InstallRoot
  Installation directory. Defaults to D:\ComfyUI.

.PARAMETER TorchBackend
  rocm (default), directml, or cpu.

.PARAMETER RocmIndex
  Wheel index for the ROCm nightly builds. Defaults to the gfx1151 Windows index.

.PARAMETER TorchVersion
  Exact torch build to install (must belong to $RocmIndex).

.PARAMETER TorchVisionVersion
  Exact torchvision build; pick the one built on the same date as TorchVersion.

.PARAMETER Port
  ComfyUI port written into the launcher.

.PARAMETER SkipDownload
  Reuse an existing archive under <InstallRoot>\downloads.

.PARAMETER Force
  Redownload / reinstall even when the target already looks complete.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\Install-ComfyUI.ps1 -InstallRoot D:\ComfyUI
#>
[CmdletBinding()]
param(
  [string]$InstallRoot = 'D:\ComfyUI',
  [ValidateSet('rocm', 'directml', 'cpu')][string]$TorchBackend = 'rocm',
  [string]$RocmIndex = 'https://rocm.nightlies.amd.com/v2/gfx1151/',
  [string]$TorchVersion = '2.10.0+rocm7.13.0a20260512',
  [string]$TorchVisionVersion = '0.25.0+rocm7.13.0a20260512',
  [int]$Port = 8188,
  [switch]$SkipDownload,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$PortableDir = Join-Path $InstallRoot 'ComfyUI_windows_portable'
$DownloadDir = Join-Path $InstallRoot 'downloads'
$Archive = Join-Path $DownloadDir 'ComfyUI_windows_portable_nvidia.7z'
$LogsDir = Join-Path $InstallRoot 'logs'
$ReleaseUrl = 'https://github.com/comfyanonymous/ComfyUI/releases/latest/download/ComfyUI_windows_portable_nvidia.7z'
$Python = Join-Path $PortableDir 'python_embeded\python.exe'
$MainPy = Join-Path $PortableDir 'ComfyUI\main.py'

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "   OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "   !   $msg" -ForegroundColor Yellow }

function Download-Portable {
  if ((Test-Path $Archive) -and -not $Force) {
    Ok "archive already present: $Archive"
    return
  }
  New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
  Step "Downloading ComfyUI portable (~2 GB)"
  $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
  if ($bits) {
    try {
      Start-BitsTransfer -Source $ReleaseUrl -Destination $Archive -Description 'ComfyUI portable' -ErrorAction Stop
      Ok 'downloaded via BITS'
      return
    } catch { Warn "BITS failed: $($_.Exception.Message); falling back to Invoke-WebRequest" }
  }
  Invoke-WebRequest -Uri $ReleaseUrl -OutFile $Archive -UseBasicParsing
  Ok "downloaded: $Archive"
}

function Extract-Portable {
  if ((Test-Path $MainPy) -and -not $Force) {
    Ok "portable build already extracted: $PortableDir"
    return
  }
  Step 'Extracting portable build'
  $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
  if (-not $tar) {
    throw 'tar.exe not found (Windows 10 1803+ ships bsdtar). Extract the archive manually with 7-Zip into ' + $InstallRoot
  }
  & tar.exe -xf $Archive -C $InstallRoot
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $MainPy)) {
    throw "extraction failed (exit $LASTEXITCODE). Extract $Archive into $InstallRoot manually, then re-run with -SkipDownload."
  }
  Ok "extracted to $PortableDir"
}

function Install-TorchRocm {
  Step "Installing ROCm PyTorch ($TorchVersion)"
  & $Python -m pip uninstall -y torch torchvision torchaudio 2>&1 | Out-Null
  & $Python -m pip install --index-url $RocmIndex --pre --no-cache-dir "torch==$TorchVersion" "torchvision==$TorchVisionVersion"
  if ($LASTEXITCODE -ne 0) {
    throw "pip install failed. Check that $RocmIndex still hosts $TorchVersion and $TorchVisionVersion; override with -TorchVersion / -TorchVisionVersion / -RocmIndex."
  }
  Ok 'ROCm wheels installed'
}

function Install-TorchDirectML {
  Step 'Installing torch-directml'
  & $Python -m pip uninstall -y torch torchvision torchaudio 2>&1 | Out-Null
  & $Python -m pip install torch-directml 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'torch-directml install failed' }
  Ok 'torch-directml installed (start ComfyUI with --directml)'
}

function Verify-Torch {
  Step 'Verifying the GPU is visible to PyTorch'
  $code = 'import torch;print(torch.__version__);print(torch.cuda.is_available());print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else "no-device")'
  $out = & $Python -c $code 2>&1
  $out | ForEach-Object { Write-Host "   $_" }
  $joined = ($out | Out-String)
  if ($TorchBackend -eq 'rocm' -and $joined -notmatch 'True') {
    throw 'torch.cuda.is_available() is False. Re-run with -Force, or install a matching torch/torchvision pair from ' + $RocmIndex
  }
  Ok 'PyTorch check finished'
}

function Write-Launcher {
  $cmd = @"
@echo off
title ComfyUI ($Port)
cd /d "$PortableDir"
.\\python_embeded\\python.exe -s ComfyUI\\main.py --listen 127.0.0.1 --port $Port --disable-auto-launch
pause
"@
  Set-Content -Path (Join-Path $InstallRoot 'Start-ComfyUI.cmd') -Value $cmd -Encoding OEM
  Ok "launcher: $(Join-Path $InstallRoot 'Start-ComfyUI.cmd')"
}

function Write-Supervisor {
  $source = Join-Path $PSScriptRoot 'supervise.js'
  if (Test-Path $source) {
    Copy-Item $source (Join-Path $InstallRoot 'supervise.js') -Force
    Ok "supervisor: $(Join-Path $InstallRoot 'supervise.js')"
  } else {
    Warn 'supervise.js not found next to the installer; skip lifecycle helper'
  }
}

Step "ComfyUI bootstrap -> $InstallRoot"
New-Item -ItemType Directory -Force -Path $InstallRoot, $LogsDir | Out-Null

if (-not $SkipDownload) { Download-Portable } else { Warn 'skip download: assuming an archive under downloads' }
Extract-Portable

switch ($TorchBackend) {
  'rocm' { Install-TorchRocm }
  'directml' { Install-TorchDirectML }
  'cpu' { Warn 'cpu backend: keeping the bundled torch, generation will be slow' }
}

Verify-Torch
Write-Launcher
Write-Supervisor

Step 'Done'
Write-Host @"
Next steps:
  1) Drop a checkpoint into $PortableDir\ComfyUI\models\checkpoints
  2) Start ComfyUI:  D:\...\Start-ComfyUI.cmd   (or: node supervise.js --idle-min 30)
  3) Open http://127.0.0.1:$Port

Backend: $TorchBackend   Port: $Port   Root: $InstallRoot
"@
