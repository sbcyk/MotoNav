<#
.SYNOPSIS
  刷 MotoNav 固件到 1.75 圆屏。默认只写 app 分区（0x10000），保留 NVS。

.DESCRIPTION
  自动找 Espressif 串口、自动挑 dist 里最新的镜像、写完整重校验。
  不给参数就是「找串口 + 刷最新 app 镜像」，日常最常用这一条。

.PARAMETER Build
  刷之前先跑 firmware/build.py 编一次（首次约 6.5 分钟，增量 1~2 分钟）。

.PARAMETER Port
  指定串口，如 COM4。不给就按 Espressif VID（303A）自动找；找到多个会列出来。

.PARAMETER Bin
  指定镜像。不给就按时间挑 dist/175/panel0 里最新的一个。

.PARAMETER Full
  整片刷：先 erase-flash，再写 0x0 的 full 镜像。**会清空 NVS**（配对、屏幕方向、
  开机品牌、主题包全丢），只有救砖才用。默认要交互确认。

.PARAMETER Force
  配合 -Full 跳过确认。只在自动化里用。

.PARAMETER DryRun
  只打印将要执行的命令，不真的刷。

.PARAMETER Baud
  烧录波特率，默认 460800。线材差、经常掉线时降到 230400。

.EXAMPLE
  pwsh -File firmware/flash-dev.ps1

.EXAMPLE
  pwsh -File firmware/flash-dev.ps1 -Build

.EXAMPLE
  pwsh -File firmware/flash-dev.ps1 -Port COM7 -Bin firmware/dist/175/panel0/xxx_app_0x10000.bin
#>

# 需要 PowerShell 7：下面用到 ?. 和 -in。放在帮助块之后，否则 Get-Help 认不出这段注释。
#Requires -Version 7.0

[CmdletBinding()]
param(
  [switch]$Build,
  [string]$Port,
  [string]$Bin,
  [switch]$Full,
  [switch]$Force,
  [switch]$DryRun,
  [int]$Baud = 460800
)

$ErrorActionPreference = 'Stop'

$FwDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dist  = Join-Path $FwDir 'dist/175/panel0'
$Src   = Join-Path $FwDir 'boards/175/MotoNav'

function Write-Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Note([string]$text) { Write-Host "    $text" -ForegroundColor Gray }
function Write-Problem([string]$text) { Write-Host "!!  $text" -ForegroundColor Yellow }

# ---------- 找 esptool ----------
function Find-Esptool {
  $root = Join-Path $env:LOCALAPPDATA 'Arduino15/packages/esp32/tools/esptool_py'
  if (Test-Path -LiteralPath $root) {
    $hit = Get-ChildItem -LiteralPath $root -Directory |
      Sort-Object { try { [version]$_.Name } catch { [version]'0.0.0' } } -Descending |
      ForEach-Object { Join-Path $_.FullName 'esptool.exe' } |
      Where-Object { Test-Path -LiteralPath $_ } |
      Select-Object -First 1
    if ($hit) { return $hit }
  }
  $onPath = Get-Command esptool.exe -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  throw "找不到 esptool.exe。装 Arduino ESP32 core 后它会在 %LOCALAPPDATA%\Arduino15\packages\esp32\tools\esptool_py\ 下。"
}

# ---------- 找串口 ----------
# 只认 Espressif 原生 USB（VID 303A）。板子若走 CH340 / CP210x 转接板，
# 这里找不到，用 -Port 手动指定。
function Find-EspPort {
  $ports = @(
    Get-CimInstance Win32_PnPEntity |
      Where-Object { $_.DeviceID -like 'USB\VID_303A*' -and $_.Name -match '\(COM\d+\)' } |
      ForEach-Object { [regex]::Match($_.Name, '(COM\d+)').Groups[1].Value } |
      Select-Object -Unique
  )
  if ($ports.Count -eq 0) {
    throw '没找到 Espressif（VID_303A）串口：换一根能传数据的线，或者确认板子插好了。'
  }
  if ($ports.Count -gt 1) {
    Write-Problem "找到多个 Espressif 串口：$($ports -join '、')"
    throw '串口不唯一，用 -Port 指定一个。'
  }
  return $ports[0]
}

# ---------- 挑镜像 ----------
function Find-Image([bool]$isFull) {
  if (-not (Test-Path -LiteralPath $Dist)) {
    throw "dist 不存在，先编译：pwsh -File firmware/flash-dev.ps1 -Build"
  }
  $pattern = if ($isFull) { '*_full_0x0.bin' } else { '*_app_0x10000.bin' }
  $img = Get-ChildItem -LiteralPath $Dist -Filter $pattern |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $img) { throw "dist 里没有 $pattern，先编译。" }
  return $img
}

# ---------- 编译 ----------
function Invoke-Build {
  $python = (Get-Command python -ErrorAction SilentlyContinue)?.Source
  if (-not $python) {
    $fallback = 'C:\Users\codem\AppData\Local\Programs\Python\Python313\python.exe'
    if (-not (Test-Path -LiteralPath $fallback)) { throw '找不到 python。' }
    $python = $fallback
  }

  $cli = 'C:\Program Files\Arduino CLI\arduino-cli.exe'
  if (-not (Test-Path -LiteralPath $cli)) { throw "找不到 arduino-cli：$cli" }

  Write-Step '编译固件'
  & $python (Join-Path $FwDir 'build.py') --cli $cli --jobs 4
  if ($LASTEXITCODE -ne 0) { throw '编译失败，没有刷。' }
}

# ---------- 镜像是否比源码旧 ----------
function Get-StaleSource($img) {
  if (-not (Test-Path -LiteralPath $Src)) { return $null }
  $newest = Get-ChildItem -LiteralPath $Src -Recurse -File |
    Where-Object { $_.Extension -in '.h', '.ino', '.cpp', '.c' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($newest -and $newest.LastWriteTime -gt $img.LastWriteTime) { return $newest }
  return $null
}

# ---------- 主流程 ----------
$esptool = Find-Esptool

if ($Build) { Invoke-Build }

if ($Bin) {
  if (-not (Test-Path -LiteralPath $Bin)) { throw "镜像不存在：$Bin" }
  $image = Get-Item -LiteralPath $Bin
  if ($image -is [System.IO.DirectoryInfo]) { throw "$Bin 是目录，要指到具体的 .bin 文件。" }
  # 整片刷必须用 full 镜像：拿 app 镜像写 0x0 会直接刷成砖
  if ($Full -and $image.Name -notlike '*_full_0x0.bin') {
    throw "-Full 只能用 *_full_0x0.bin 整片镜像，$($image.Name) 是 app 镜像，写 0x0 会变砖。"
  }
  # 反过来的坑：full 镜像从 0x10000 开始写，只会写坏 app 分区
  if (-not $Full -and $image.Name -like '*_full_0x0.bin') {
    throw "$($image.Name) 是整片镜像，要从 0x0 写；要么加 -Full（会清 NVS），要么换 *_app_0x10000.bin。"
  }
} else {
  $image = Find-Image -isFull ([bool]$Full)
}

$stale = Get-StaleSource $image
if ($stale) {
  Write-Problem "镜像比源码旧（$($stale.Name) 改过），刷上去还是旧固件；要刷新代码加 -Build。"
}

if ($Full) {
  Write-Problem '整片刷会清空 NVS：配对、屏幕方向、开机品牌、主题包全丢，之后要重新配对。'
  if (-not $Force -and -not $DryRun) {
    $answer = Read-Host '确认整片刷？输入 yes 继续'
    if ($answer -ne 'yes') { Write-Host '已取消。'; exit 1 }
  }
}

if (-not $Port) {
  if ($DryRun) {
    # 空跑不碰硬件：端口找不到就用占位，别让「只想看一眼命令」的人卡在这里
    try { $Port = Find-EspPort } catch { $Port = 'COM4'; Write-Problem "没找到串口，空跑用占位 $Port" }
  } else {
    $Port = Find-EspPort
  }
}

# 文件名形如 MotoNav_universal_1.75_v2.5.0_panel0_app_0x10000.bin
$ver = if ($image.Name -match '(v\d+\.\d+\.\d+)') { $Matches[1] } else { '未知版本' }
$offset = if ($Full) { '0x0' } else { '0x10000' }
$target = if ($Full) { '0x0（整片，清 NVS）' } else { '0x10000（app 分区，保留 NVS）' }

$rule = '-' * 46
Write-Host $rule -ForegroundColor DarkGray
Write-Note "串口  $Port"
Write-Note "镜像  $($image.Name)"
Write-Note "版本  $ver"
Write-Note "大小  $($image.Length) 字节"
Write-Note "写入  $target"
Write-Host $rule -ForegroundColor DarkGray

# esptool 5.x 的子命令是连字符（write-flash / erase-flash）；4.x 是下划线，降级要一起改。
$espArgs = @('--chip', 'esp32s3', '-p', $Port, '-b', $Baud)

if ($DryRun) {
  if ($Full) { Write-Host "将执行: $esptool $($espArgs -join ' ') erase-flash" }
  Write-Host "将执行: $esptool $($espArgs -join ' ') write-flash $offset $($image.FullName)"
  Write-Host '（-DryRun，什么都没做）'
  exit 0
}

if ($Full) {
  Write-Step '擦除整片'
  & $esptool @espArgs erase-flash
  if ($LASTEXITCODE -ne 0) { throw '擦除失败，没往下写。' }
}

Write-Step "写入 $ver"
& $esptool @espArgs write-flash $offset $image.FullName

if ($LASTEXITCODE -ne 0) {
  Write-Problem '刷写失败。常见原因：串口被串口监视器或 Arduino IDE 占着、板子没进下载模式、线材只能充电。'
  exit $LASTEXITCODE
}

Write-Host $rule -ForegroundColor DarkGray
Write-Host "OK：$ver 已写入，写完做了 hash 校验。板子会自动重启，点屏幕看信息浮层里的版本号确认。" -ForegroundColor Green
if (-not $Full) { Write-Host 'NVS 没动：配对、屏幕方向、开机品牌、主题包都还在。' -ForegroundColor Green }
