# Astra Windows 构建环境一键配置（在 Windows 虚拟机内以「管理员」身份运行）
# 用法：
#   powershell -ExecutionPolicy Bypass -File provision_windows.ps1 -HostUrl http://10.0.2.2:8000
param(
  [string]$HostUrl = 'http://10.0.2.2:8000'
)

$ErrorActionPreference = 'Stop'
function Step($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 1. 基础检查
Step '1/5 检查 winget 与长路径支持'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host '未找到 winget，请先在 Microsoft Store 更新「应用安装程序」后重试。' -ForegroundColor Red
  exit 1
}
git config --system core.longpaths true 2>$null

# ---------------------------------------------------------------- 2. Git
Step '2/5 安装 Git'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  winget install --id Git.Git -e --source winget --silent `
    --accept-package-agreements --accept-source-agreements
}
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

# ---------------------------------------------------------------- 3. Visual Studio C++ 工具链
Step '3/5 安装 Visual Studio 2022 生成工具（C++ 桌面开发）'
$vsPath = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools'
if (-not (Test-Path $vsPath)) {
  winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget `
    --accept-package-agreements --accept-source-agreements `
    --override "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
} else {
  Write-Host '已安装，跳过。'
}

# ---------------------------------------------------------------- 4. Flutter SDK
Step '4/5 安装 Flutter SDK'
$flutterRoot = 'C:\src\flutter'
if (-not (Test-Path "$flutterRoot\bin\flutter.bat")) {
  New-Item -ItemType Directory -Force -Path 'C:\src' | Out-Null
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git $flutterRoot
}
$env:Path = "$flutterRoot\bin;$env:Path"
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*$flutterRoot\bin*") {
  [System.Environment]::SetEnvironmentVariable('Path', "$flutterRoot\bin;$machinePath", 'Machine')
}
flutter config --enable-windows-desktop | Out-Null
flutter --version

# ---------------------------------------------------------------- 5. 拉取项目
Step '5/5 下载项目并安装依赖'
$zip = Join-Path $env:TEMP 'astra_flutter.zip'
$dst = 'C:\work'
if (-not (Test-Path $zip)) {
  Invoke-WebRequest -Uri "$HostUrl/astra_flutter.zip" -OutFile $zip
}
if (Test-Path "$dst\astra_flutter") { Remove-Item "$dst\astra_flutter" -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Expand-Archive -Path $zip -DestinationPath $dst -Force

Set-Location "$dst\astra_flutter"
flutter pub get
flutter doctor -v

Write-Host "`n环境准备完成。构建命令：" -ForegroundColor Green
Write-Host "  cd C:\work\astra_flutter"
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1"
