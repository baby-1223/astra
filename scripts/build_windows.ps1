# Astra Windows 构建脚本
#
# 用法（在 Windows PowerShell 中，于项目任意目录执行）：
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 -SkipTests
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 -Clean -NoZip
#
# 产物：build\windows\x64\runner\Release\（Astra.exe + DLL + data）
#       dist\Astra-win-x64-<版本>-<日期>.zip（未指定 -NoZip 时）

[CmdletBinding()]
param(
    [switch]$SkipTests,  # 跳过 flutter test
    [switch]$NoZip,      # 不生成 zip 压缩包
    [switch]$Clean       # 构建前执行 flutter clean
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "构建失败：$Message" -ForegroundColor Red
    exit 1
}

# 1. 环境检查
Write-Step "检查 Flutter 环境"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail "未找到 flutter 命令，请先安装 Flutter SDK 并加入 PATH。"
}
flutter --version
if ($LASTEXITCODE -ne 0) { Fail "flutter 命令执行异常。" }

Write-Step "检查 Visual Studio C++ 工具链"
# 原生命令的 stderr 在 2>&1 下可能被当作错误，临时放宽错误处理
$previousEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$doctor = flutter doctor -v 2>&1 | Out-String
$ErrorActionPreference = $previousEap
if ($doctor -notmatch "Visual Studio[^\r\n]*✓") {
    Write-Host "警告：flutter doctor 未检测到可用的 Visual Studio C++ 工具链。" -ForegroundColor Yellow
    Write-Host "请安装 Visual Studio 2022 并勾选「使用 C++ 的桌面开发」工作负载。" -ForegroundColor Yellow
}

# 2. 清理与依赖
if ($Clean) {
    Write-Step "清理构建目录"
    flutter clean
    if ($LASTEXITCODE -ne 0) { Fail "flutter clean 失败。" }
}

Write-Step "启用 Windows 桌面支持"
flutter config --enable-windows-desktop | Out-Null

Write-Step "拉取依赖"
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get 失败。" }

# 3. 静态检查与测试
Write-Step "静态分析"
flutter analyze
if ($LASTEXITCODE -ne 0) { Fail "flutter analyze 发现问题，请先修复。" }

if (-not $SkipTests) {
    Write-Step "运行测试"
    flutter test
    if ($LASTEXITCODE -ne 0) { Fail "测试未通过。" }
}

# 4. 构建 Release
Write-Step "构建 Windows Release"
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Fail "flutter build windows 失败。" }

$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$ExePath = Join-Path $ReleaseDir "Astra.exe"
if (-not (Test-Path $ExePath)) {
    Fail "未找到产物 $ExePath"
}

# 5. 打包 zip
$ZipPath = ""
if (-not $NoZip) {
    Write-Step "打包发布文件"
    $versionLine = Select-String -Path (Join-Path $ProjectRoot "pubspec.yaml") -Pattern '^version:\s*(\S+)' |
        Select-Object -First 1
    $version = if ($versionLine) { $versionLine.Matches[0].Groups[1].Value } else { "dev" }
    $version = $version -replace '[+]', '-build'
    $stamp = Get-Date -Format "yyyyMMdd"

    $distDir = Join-Path $ProjectRoot "dist"
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
    $ZipPath = Join-Path $distDir "Astra-win-x64-$version-$stamp.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath -CompressionLevel Optimal
}

# 6. 结果汇总
$sizeMb = [math]::Round((Get-ChildItem $ReleaseDir -Recurse -File |
    Measure-Object -Property Length -Sum).Sum / 1MB, 1)

Write-Host ""
Write-Host "构建完成" -ForegroundColor Green
Write-Host "  可执行文件：$ExePath"
Write-Host "  发布目录  ：$ReleaseDir（约 $sizeMb MB）"
if ($ZipPath -ne "") { Write-Host "  压缩包    ：$ZipPath" }
Write-Host ""
Write-Host "提示：分发时需保留 Release 目录内的 DLL 与 data 文件夹，不能只拷贝 Astra.exe。"
