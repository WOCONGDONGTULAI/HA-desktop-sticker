@echo off
chcp 65001 >nul
rem 源码方式启动（改代码时用这个）
dotnet run --project "%~dp0HASticker.csproj"
pause
