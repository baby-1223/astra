@echo off
chcp 65001 >nul
setlocal
rem Astra Windows 一键构建：双击运行或在命令行追加参数，例如 build_windows.bat -SkipTests
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" %*
if errorlevel 1 (
    echo.
    echo 构建失败，请查看上方日志。
) else (
    echo.
    echo 构建成功。
)
pause
