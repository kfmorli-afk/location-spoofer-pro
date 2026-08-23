@echo off
chcp 65001 >nul
title Location Spoofer Pro - GitHub Push
echo =======================================================
echo   Location Spoofer Pro - Upload zu GitHub
echo =======================================================
echo.
cd /d "%~dp0"
echo Lade Dateien zu https://github.com/kfmorli-afk/location-spoofer-pro.git hoch...
echo.
git push -u origin main
echo.
if %ERRORLEVEL% equ 0 (
    echo =======================================================
    echo [OK] Erfolgreich hochgeladen!
    echo.
    echo Gehe jetzt zu:
    echo https://github.com/kfmorli-afk/location-spoofer-pro/actions
    echo.
    echo Der automatische IPA-Build startet dort in kuerze!
    echo =======================================================
) else (
    echo [!] Fehler beim Hochladen. Bitte pruefe deine GitHub-Anmeldedaten.
)
echo.
pause
