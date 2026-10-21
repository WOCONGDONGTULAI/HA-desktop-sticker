@echo off
chcp 65001 >nul
setlocal

echo ============================
echo   HA 贴纸 - 发布 Windows 版
echo ============================
echo.

where dotnet >nul 2>nul
if errorlevel 1 (
    echo 没找到 dotnet，先装 .NET 8 SDK：
    echo https://dotnet.microsoft.com/download
    pause
    exit /b 1
)

echo 正在发布（单文件 exe）...
dotnet publish "%~dp0HASticker.csproj" -c Release -r win-x64 --self-contained false ^
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true ^
    -o "%~dp0publish"

if errorlevel 1 (
    echo.
    echo 发布失败，看看上面的报错。
    pause
    exit /b 1
)

echo.
echo 完成： %~dp0publish\HASticker.exe
echo 把它复制到一个固定目录（不要放 C:\Program Files，WebView2 需要可写目录），双击就能跑。
echo.
pause
